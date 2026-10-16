"""Offline tests of arr-sync against a fake Servarr API.

The fake behaves like Radarr/Sonarr v3 where it matters: privacy fields are
masked as "********" in every response and a mask sent back keeps the stored
value; providers live in a WAL-mode SQLite database like the real one; the
create of an enabled provider runs Test() (forceSave or not), and so does a
changed update of one unless forceSave=true; validation errors echo
attempted values. Faults (429 with
Retry-After, 5xx, a dropped connection after applying) can be injected.

usage: arr-sync-test.py <dir holding arr_sync.py>
"""

import contextlib
import copy
import hashlib
import io
import json
import os
import socket
import sqlite3
import sys
import tempfile
import threading
import unittest
import unittest.mock
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, sys.argv.pop(1))
import arr_sync  # noqa: E402

MASK = "********"
BOT_TOKEN = "synthetic-bot-token-1"
OTHER_TOKEN = "synthetic-bot-token-2"
CHAT_ID = "-100000000001"
QBIT_PASSWORD = "synthetic-qbit-password"
SECRETS = [BOT_TOKEN, OTHER_TOKEN, CHAT_ID, QBIT_PASSWORD]
TABLES = {"downloadclient": "DownloadClients", "notification": "Notifications"}


def field(name, value, privacy="normal"):
    return {"name": name, "value": value, "privacy": privacy}


def telegram_schema():
    return {
        "id": 0,
        "name": "",
        "implementation": "Telegram",
        "configContract": "TelegramSettings",
        "tags": [],
        "includeHealthWarnings": False,
        "onGrab": False,
        "onDownload": False,
        "onUpgrade": False,
        "onRename": False,
        "onMovieDelete": False,
        "supportsOnGrab": True,
        "supportsOnDownload": True,
        "supportsOnUpgrade": True,
        "supportsOnRename": False,
        "supportsOnMovieDelete": True,
        "fields": [
            field("botToken", "", "apiKey"),
            field("chatId", ""),
            field("topicId", None),
            field("sendSilently", False),
            field("metadataLinks", []),
        ],
    }


def webhook_schema():
    return {
        "id": 0,
        "name": "",
        "implementation": "Webhook",
        "configContract": "WebhookSettings",
        "tags": [],
        "includeHealthWarnings": False,
        "onGrab": False,
        "onUpgrade": False,
        "supportsOnGrab": True,
        "supportsOnUpgrade": True,
        "fields": [
            field("url", ""),
            field("method", 1),
            field("username", "", "userName"),
            field("password", "", "password"),
            field("headers", []),
        ],
    }


def qbit_schema():
    return {
        "id": 0,
        "name": "",
        "implementation": "QBittorrent",
        "configContract": "QBittorrentSettings",
        "enable": True,
        "protocol": "torrent",
        "priority": 1,
        "removeCompletedDownloads": True,
        "removeFailedDownloads": True,
        "tags": [],
        "fields": [
            field("host", "localhost"),
            field("port", 8080),
            field("useSsl", False),
            field("username", "", "userName"),
            field("password", "", "password"),
            field("movieCategory", "radarr"),
            field("olderMoviePriority", 0),
        ],
    }


def default_settings():
    return {
        "config/naming": {
            "id": 1,
            "renameMovies": False,
            "colonReplacementFormat": "delete",
            "standardMovieFormat": "{Movie Title} ({Release Year}) {Quality Full}",
            "movieFolderFormat": "{Movie Title} ({Release Year})",
        },
        "config/mediamanagement": {
            "id": 1,
            "copyUsingHardlinks": True,
            "minimumFreeSpaceWhenImporting": 100,
            "recycleBin": "",
        },
        "delayprofile/1": {
            "id": 1,
            "enableUsenet": True,
            "enableTorrent": True,
            "preferredProtocol": "usenet",
            "order": 2147483647,
            "tags": [],
        },
    }


def default_quality_definitions():
    return [
        {
            "id": 1,
            "quality": {"id": 4, "name": "HDTV-720p"},
            "title": "HDTV-720p",
            "weight": 14,
            "minSize": 0,
            "maxSize": 100,
            "preferredSize": 95,
        },
        {
            "id": 2,
            "quality": {"id": 7, "name": "Bluray-1080p"},
            "title": "Bluray-1080p",
            "weight": 19,
            "minSize": 0,
            "maxSize": 100,
            "preferredSize": 95,
        },
    ]


def default_profiles():
    return [
        {
            "id": 5,
            "name": "Any",
            "upgradeAllowed": True,
            "cutoff": 31,
            "language": {"id": 1, "name": "English"},
            "items": [{"quality": {"id": 4, "name": "HDTV-720p"}, "allowed": True}],
            "formatItems": [{"format": 1, "name": "HDR", "score": 500}],
            "minFormatScore": 0,
        }
    ]


class FakeServarr:
    """A Radarr-shaped API plus the database it keeps provider settings in."""

    def __init__(self, db_path):
        self.db_path = db_path
        self.schemas = {
            "notification": [telegram_schema(), webhook_schema()],
            "downloadclient": [qbit_schema()],
        }
        self.providers = {"notification": [], "downloadclient": []}
        self.settings = default_settings()
        self.quality_definitions = default_quality_definitions()
        self.profiles = default_profiles()
        self.rootfolders = []
        self.next_id = {"notification": 1, "downloadclient": 1}
        self.requests = []
        self.tests_run = []
        self.faults = []
        self.lock = threading.Lock()
        con = sqlite3.connect(db_path, check_same_thread=False)
        con.execute("PRAGMA journal_mode=WAL")
        for table in TABLES.values():
            con.execute(
                f"CREATE TABLE {table} (Id INTEGER PRIMARY KEY, Name TEXT, Settings TEXT)"
            )
        con.commit()
        # the app keeps its connection open, which keeps the -wal/-shm files
        self.con = con

    # -- state helpers -----------------------------------------------------

    def add(self, kind, resource):
        resource = copy.deepcopy(resource)
        resource.setdefault("id", self.next_id[kind])
        self.next_id[kind] = max(self.next_id[kind], resource["id"]) + 1
        self.providers[kind].append(resource)
        self.store(kind, resource)
        return resource

    def store(self, kind, resource):
        settings = {f["name"]: f.get("value") for f in resource["fields"]}
        self.con.execute(
            f"INSERT OR REPLACE INTO {TABLES[kind]} (Id, Name, Settings) VALUES (?, ?, ?)",
            (resource["id"], resource["name"], json.dumps(settings)),
        )
        self.con.commit()

    def stored(self, kind, resource_id):
        return next(r for r in self.providers[kind] if r["id"] == resource_id)

    def field_value(self, kind, resource_id, name):
        resource = self.stored(kind, resource_id)
        return next(f["value"] for f in resource["fields"] if f["name"] == name)

    def writes(self):
        return [r for r in self.requests if r[0] != "GET"]

    @staticmethod
    def masked(resource):
        out = copy.deepcopy(resource)
        for f in out.get("fields", []):
            if f.get("privacy", "normal") != "normal" and f.get("value") not in (
                "",
                None,
            ):
                f["value"] = MASK
        return out

    @staticmethod
    def enabled(kind, resource):
        if kind == "downloadclient":
            return resource.get("enable", False)
        return any(
            v for k, v in resource.items() if k.startswith("on") and k[2:3].isupper()
        )

    def merge_fields(self, old, new):
        """A mask sent back keeps the stored value, as Servarr does."""
        stored = {f["name"]: f.get("value") for f in old.get("fields", [])}
        for f in new.get("fields", []):
            if f.get("value") == MASK:
                f["value"] = stored.get(f["name"], "")
        return new

    def validate(self, resource):
        if not resource.get("name"):
            return [
                {
                    "propertyName": "Name",
                    "errorMessage": "Name must not be empty",
                    "attemptedValue": json.dumps(resource.get("fields")),
                }
            ]
        return None

    # -- request handling --------------------------------------------------

    def handle(self, method, path, query, body):
        """Returns (status, payload); payload None for an empty body."""
        if path.startswith("/api/v3"):
            path = path[len("/api/v3") :]
        force = query.get("forceSave") == ["true"]
        kind = path.strip("/").split("/")[0]
        rest = path.strip("/").split("/")[1:]
        if method == "GET":
            if path == "/system/status":
                return 200, {"appName": "Radarr", "version": "6.4.4"}
            if kind in self.providers and rest == ["schema"]:
                return 200, self.schemas[kind]
            if kind in self.providers and not rest:
                return 200, [self.masked(r) for r in self.providers[kind]]
            if path.strip("/") in self.settings:
                return 200, self.settings[path.strip("/")]
            if path == "/qualitydefinition":
                return 200, self.quality_definitions
            if path == "/qualityprofile":
                return 200, self.profiles
            if path == "/rootfolder":
                return 200, self.rootfolders
            return 404, {"message": "NotFound"}
        if kind in self.providers:
            errors = self.validate(body)
            if errors:
                return 400, errors
            if method == "POST" and not rest:
                body.pop("id", None)
                # Servarr tests every enabled provider it creates, forceSave or not
                if self.enabled(kind, body):
                    self.tests_run.append((kind, body["name"]))
                created = self.add(kind, self.merge_fields({}, body))
                return 201, self.masked(created)
            if method == "PUT" and len(rest) == 1:
                old = self.stored(kind, int(rest[0]))
                new = self.merge_fields(old, body)
                new["id"] = old["id"]
                if self.enabled(kind, new) and not force and new != old:
                    self.tests_run.append((kind, new["name"]))
                self.providers[kind][self.providers[kind].index(old)] = new
                self.store(kind, new)
                return 202, self.masked(new)
        if method == "PUT":
            key = "/".join([kind] + rest[:-1])
            if (
                key in self.settings
                and rest
                and rest[-1] == str(self.settings[key]["id"])
            ):
                self.settings[key] = body
                return 202, body
            key = "/".join([kind] + rest)
            if key in self.settings:
                self.settings[key] = body
                return 202, body
            if kind == "qualitydefinition":
                index = next(
                    i
                    for i, d in enumerate(self.quality_definitions)
                    if d["id"] == int(rest[0])
                )
                self.quality_definitions[index] = body
                return 202, body
            if kind == "qualityprofile":
                index = next(
                    i for i, p in enumerate(self.profiles) if p["id"] == int(rest[0])
                )
                self.profiles[index] = body
                return 202, body
        if method == "POST" and path == "/rootfolder":
            body["id"] = len(self.rootfolders) + 1
            self.rootfolders.append(body)
            return 201, body
        return 405, {"message": "unsupported"}


def make_handler(fake):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _serve(self, method):
            parsed = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(parsed.query)
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length)) if length else None
            if self.headers.get("X-Api-Key") != "synthetic-api-key":
                self.send_response(401)
                self.end_headers()
                return
            with fake.lock:
                fake.requests.append(
                    (method, parsed.path.replace("/api/v3", ""), query)
                )
                fault = next(
                    (
                        f
                        for f in fake.faults
                        if f["method"] == method and parsed.path.endswith(f["path"])
                    ),
                    None,
                )
                if fault:
                    fake.faults.remove(fault)
                if fault and fault["kind"] in ("429", "500"):
                    self.send_response(int(fault["kind"]))
                    if "retryAfter" in fault:
                        self.send_header("Retry-After", fault["retryAfter"])
                    self.end_headers()
                    return
                status, payload = fake.handle(method, parsed.path, query, body)
            if fault and fault["kind"] == "garbled":
                self.send_response(200)
                self.send_header("Content-Length", "5")
                self.end_headers()
                self.wfile.write(b"{oops")
                return
            if fault and fault["kind"] == "drop":
                # applied, but the client never hears back
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                return
            data = json.dumps(payload).encode() if payload is not None else b""
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self._serve("GET")

        def do_POST(self):
            self._serve("POST")

        def do_PUT(self):
            self._serve("PUT")

        def do_DELETE(self):
            self._serve("DELETE")

    return Handler


class ArrSyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.fake = FakeServarr(os.path.join(self.dir, "radarr.db"))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.fake))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.sleeps = []
        self.patch = unittest.mock.patch.object(
            arr_sync.Api, "sleep", lambda _self, s: self.sleeps.append(s)
        )
        self.patch.start()
        self.files = {}
        for name, value in {
            "api-key": "synthetic-api-key",
            "bot-token": BOT_TOKEN,
            "chat-id": CHAT_ID,
            "qbit-password": QBIT_PASSWORD,
        }.items():
            path = os.path.join(self.dir, name)
            with open(path, "w") as handle:
                handle.write(value + "\n")
            self.files[name] = path
        self.backups = os.path.join(self.dir, "backups")
        os.mkdir(self.backups)

    def tearDown(self):
        self.patch.stop()
        self.server.shutdown()
        self.server.server_close()
        self.fake.con.close()
        self.tmp.cleanup()

    # -- spec and fixtures -------------------------------------------------

    def spec(self, **overrides):
        spec = {
            "name": "radarr",
            "url": f"http://127.0.0.1:{self.server.server_address[1]}",
            "apiVersion": "v3",
            "apiKeyFile": self.files["api-key"],
            "database": self.fake.db_path,
            "rootFolders": ["/media/movies"],
            "downloadClients": [
                {
                    "name": "qBittorrent",
                    "implementation": "QBittorrent",
                    "properties": {
                        "enable": True,
                        "priority": 1,
                        "protocol": "torrent",
                    },
                    "fields": {
                        "host": "localhost",
                        "port": 8080,
                        "movieCategory": "radarr",
                    },
                    "secretFields": {"password": self.files["qbit-password"]},
                }
            ],
            "notifications": [
                {
                    "id": 2,
                    "name": "Telegram Group",
                    "implementation": "Telegram",
                    "properties": {
                        "onGrab": False,
                        "onDownload": False,
                        "onUpgrade": True,
                        "onRename": False,
                        "onMovieDelete": True,
                        "includeHealthWarnings": False,
                        "tags": [],
                    },
                    "fields": {
                        "topicId": 15,
                        "sendSilently": True,
                        "metadataLinks": [1],
                    },
                    "secretFields": {
                        "botToken": self.files["bot-token"],
                        "chatId": self.files["chat-id"],
                    },
                }
            ],
            "settings": {
                "config/naming": {
                    "renameMovies": True,
                    "colonReplacementFormat": "smart",
                    "standardMovieFormat": "{Movie CleanTitle} {(Release Year)}",
                },
                "config/mediamanagement": {"minimumFreeSpaceWhenImporting": 10000},
                "delayprofile/1": {"preferredProtocol": "usenet", "tags": []},
            },
            "qualityDefinitions": {
                "HDTV-720p": {
                    "title": "HDTV-720p",
                    "minSize": 17.1,
                    "preferredSize": 1999,
                    "maxSize": None,
                }
            },
            "qualityProfiles": {"Any": {"language": {"id": -2, "name": "Original"}}},
        }
        spec.update(overrides)
        return spec

    def adopted(self):
        """The fake in the state the spec describes, as on hoard today."""
        self.fake.rootfolders.append({"id": 1, "path": "/media/movies"})
        dc = qbit_schema()
        dc.update(name="qBittorrent")
        set_field(dc, "password", QBIT_PASSWORD)
        set_field(dc, "olderMoviePriority", -100)
        self.fake.add("downloadclient", dc)
        tg = telegram_schema()
        tg.update(id=2, name="Telegram Group", onUpgrade=True, onMovieDelete=True)
        for name, value in {
            "botToken": BOT_TOKEN,
            "chatId": CHAT_ID,
            "topicId": 15,
            "sendSilently": True,
            "metadataLinks": [1],
        }.items():
            set_field(tg, name, value)
        self.fake.add("notification", tg)
        hook = webhook_schema()
        hook.update(id=3, name="Unmanaged hook")
        set_field(hook, "password", "synthetic-hook-password")
        self.fake.add("notification", hook)
        self.fake.settings["config/naming"].update(
            renameMovies=True,
            colonReplacementFormat="smart",
            standardMovieFormat="{Movie CleanTitle} {(Release Year)}",
        )
        self.fake.settings["config/mediamanagement"][
            "minimumFreeSpaceWhenImporting"
        ] = 10000
        self.fake.quality_definitions[0].update(
            minSize=17.1, preferredSize=1999, maxSize=None
        )
        self.fake.profiles[0]["language"] = {"id": -2, "name": "Original"}

    def apply(self, spec=None, backups=True):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            arr_sync.apply(spec or self.spec(), self.backups if backups else None)
        self.assertNoSecrets(out.getvalue())
        return out.getvalue()

    def apply_fails(self, spec=None):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), self.assertRaises(SystemExit) as caught:
            arr_sync.apply(spec or self.spec(), self.backups)
        self.assertNoSecrets(out.getvalue() + str(caught.exception))
        return out.getvalue(), str(caught.exception)

    def preview(self, spec=None, expect_no_changes=True):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = arr_sync.preview(spec or self.spec(), expect_no_changes)
        self.assertNoSecrets(out.getvalue())
        return rc, out.getvalue()

    def assertNoSecrets(self, text):
        for secret in SECRETS + ["synthetic-hook-password"]:
            self.assertNotIn(secret, text)

    # -- fresh install -----------------------------------------------------

    def test_fresh_install_converges_then_second_run_writes_nothing(self):
        out = self.apply()
        self.assertIn("converged", out)
        self.assertEqual(len(self.fake.providers["notification"]), 1)
        self.assertEqual(len(self.fake.providers["downloadclient"]), 1)
        tg = self.fake.providers["notification"][0]
        self.assertEqual(
            self.fake.field_value("notification", tg["id"], "botToken"), BOT_TOKEN
        )
        self.assertEqual(
            self.fake.field_value("notification", tg["id"], "chatId"), CHAT_ID
        )
        self.assertTrue(tg["onUpgrade"] and tg["onMovieDelete"] and not tg["onGrab"])
        self.assertEqual(
            self.fake.settings["config/naming"]["colonReplacementFormat"], "smart"
        )
        self.assertEqual(self.fake.quality_definitions[0]["minSize"], 17.1)
        self.assertIsNone(self.fake.quality_definitions[0]["maxSize"])
        self.assertEqual(self.fake.profiles[0]["language"]["id"], -2)
        self.assertEqual(self.fake.rootfolders[0]["path"], "/media/movies")
        # no notification was tested (that would send a message)
        self.assertNotIn("notification", [kind for kind, _ in self.fake.tests_run])
        before = len(self.fake.requests)
        out = self.apply()
        self.assertIn("converged, 0 write(s)", out)
        self.assertEqual([r for r in self.fake.requests[before:] if r[0] != "GET"], [])

    def test_fresh_install_without_profile_skips_it(self):
        self.fake.profiles.clear()
        out = self.apply()
        self.assertIn("quality profile 'Any' does not exist yet; skipped", out)
        self.assertFalse(
            any(r[1].startswith("/qualityprofile/") for r in self.fake.writes())
        )

    # -- adoption ----------------------------------------------------------

    def test_adoption_preview_and_apply_write_nothing(self):
        self.adopted()
        db_before = file_digest(self.fake.db_path)
        rc, out = self.preview()
        self.assertEqual(rc, 0, out)
        self.assertIn("0 write(s), 0 problem(s), 0 mismatch(es), 0 unverifiable", out)
        out = self.apply()
        self.assertIn("converged, 0 write(s)", out)
        self.assertEqual(self.fake.writes(), [])
        self.assertEqual(os.listdir(self.backups), [])
        # the database was only read
        self.assertEqual(file_digest(self.fake.db_path), db_before)

    def test_undeclared_fields_and_resources_are_preserved(self):
        self.adopted()
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.apply()
        dc = self.fake.providers["downloadclient"][0]
        self.assertEqual(
            self.fake.field_value("downloadclient", dc["id"], "olderMoviePriority"),
            -100,
        )
        self.assertEqual(
            self.fake.field_value("notification", 3, "password"),
            "synthetic-hook-password",
        )
        self.assertEqual([r[1] for r in self.fake.writes()], ["/config/naming/1"])
        naming = self.fake.settings["config/naming"]
        self.assertTrue(naming["renameMovies"])
        self.assertEqual(naming["movieFolderFormat"], "{Movie Title} ({Release Year})")
        self.assertFalse(any(r[0] == "DELETE" for r in self.fake.requests))

    def test_stable_id_wins_and_ui_rename_is_undone(self):
        self.adopted()
        self.fake.providers["notification"][0]["name"] = "Renamed in the UI"
        self.apply()
        self.assertEqual(
            [(r[0], r[1]) for r in self.fake.writes()], [("PUT", "/notification/2")]
        )
        self.assertEqual(self.fake.stored("notification", 2)["name"], "Telegram Group")
        self.assertEqual(len(self.fake.providers["notification"]), 2)

    def test_name_match_when_id_differs_after_reinstall(self):
        self.adopted()
        spec = self.spec()
        spec["notifications"][0]["id"] = 40
        rc, out = self.preview(spec)
        self.assertEqual(rc, 0, out)

    def test_id_holding_another_implementation_is_not_taken(self):
        self.adopted()
        spec = self.spec()
        spec["notifications"][0]["id"] = 3  # the webhook's id
        rc, out = self.preview(spec)
        self.assertEqual(rc, 0, out)

    # -- secrets -----------------------------------------------------------

    def test_differing_masked_secret_is_kept_not_rotated(self):
        self.adopted()
        tg = self.fake.stored("notification", 2)
        set_field(tg, "botToken", OTHER_TOKEN)
        self.fake.store("notification", tg)
        rc, out = self.preview()
        self.assertEqual(rc, 1)
        self.assertIn(
            "field botToken differs from its secret file; live value kept", out
        )
        out, error = self.apply_fails()
        self.assertIn("differ from or can't be checked", error)
        self.assertEqual(
            self.fake.field_value("notification", 2, "botToken"), OTHER_TOKEN
        )
        self.assertEqual(self.fake.writes(), [])

    def test_differing_plain_secret_is_kept(self):
        self.adopted()
        tg = self.fake.stored("notification", 2)
        set_field(tg, "chatId", "-100000000002")
        self.fake.store("notification", tg)
        rc, out = self.preview()
        self.assertEqual(rc, 1)
        self.assertIn("field chatId differs", out)
        self.apply_fails()
        self.assertEqual(
            self.fake.field_value("notification", 2, "chatId"), "-100000000002"
        )

    def test_mismatch_does_not_block_other_changes(self):
        self.adopted()
        tg = self.fake.stored("notification", 2)
        set_field(tg, "botToken", OTHER_TOKEN)
        tg["onGrab"] = True
        self.fake.store("notification", tg)
        self.apply_fails()
        tg = self.fake.stored("notification", 2)
        self.assertFalse(tg["onGrab"])
        self.assertEqual(
            self.fake.field_value("notification", 2, "botToken"), OTHER_TOKEN
        )
        # the update sent the mask back, never a token
        self.assertEqual(self.fake.tests_run, [])

    def test_empty_live_secret_is_filled(self):
        self.adopted()
        dc = self.fake.providers["downloadclient"][0]
        set_field(dc, "password", "")
        self.fake.store("downloadclient", dc)
        self.apply()
        self.assertEqual(
            self.fake.field_value("downloadclient", dc["id"], "password"), QBIT_PASSWORD
        )

    def test_masked_secret_without_database_is_unverifiable(self):
        self.adopted()
        spec = self.spec(database=None)
        rc, out = self.preview(spec)
        self.assertEqual(rc, 1)
        self.assertIn("field botToken is masked and the database can't confirm it", out)
        self.apply_fails(spec)
        self.assertEqual(self.fake.writes(), [])

    def test_unreadable_database_is_unverifiable_not_fatal(self):
        self.adopted()
        spec = self.spec(database=os.path.join(self.dir, "missing.db"))
        rc, out = self.preview(spec)
        self.assertEqual(rc, 1)
        self.assertIn("can't confirm it", out)

    def test_blank_clears_a_masked_value(self):
        self.adopted()
        spec = self.spec()
        spec["notifications"].append(
            {
                "id": 3,
                "name": "Unmanaged hook",
                "implementation": "Webhook",
                "properties": {},
                "fields": {"password": ""},
                "secretFields": {},
            }
        )
        self.apply(spec)
        self.assertEqual(self.fake.field_value("notification", 3, "password"), "")
        self.assertIn(
            ("PUT", "/notification/3", {"forceSave": ["true"]}), self.fake.writes()
        )
        self.assertIn("converged, 0 write(s)", self.apply(spec))

    def test_absent_value_equals_declared_null(self):
        # the API leaves "value" out of a field that is null, as for qBittorrent's apiKey
        self.adopted()
        dc = self.fake.providers["downloadclient"][0]
        dc["fields"].append({"name": "apiKey", "privacy": "apiKey"})
        spec = self.spec()
        spec["downloadClients"][0]["fields"]["apiKey"] = None
        rc, out = self.preview(spec)
        self.assertEqual(rc, 0, out)

    def test_private_field_with_plain_value_is_refused(self):
        spec = self.spec()
        spec["downloadClients"][0]["fields"]["password"] = "plain"
        out, error = self.apply_fails(spec)
        self.assertIn("field 'password' is private; declare it as a secret field", out)
        self.assertEqual(self.fake.writes(), [])

    def test_missing_secret_file_is_a_problem(self):
        spec = self.spec()
        spec["notifications"][0]["secretFields"]["botToken"] = os.path.join(
            self.dir, "nope"
        )
        out, _ = self.apply_fails(spec)
        self.assertIn("cannot read secret for 'botToken'", out)
        self.assertEqual(self.fake.writes(), [])

    # -- unknown and unsupported -------------------------------------------

    def test_unknown_or_unsupported_keys_write_nothing(self):
        cases = [
            (
                "notifications",
                lambda s: s[0]["fields"].update(bogus=1),
                "unknown field 'bogus'",
            ),
            (
                "notifications",
                lambda s: s[0]["properties"].update(onBogus=True),
                "unknown property 'onBogus'",
            ),
            (
                "notifications",
                lambda s: s[0]["properties"].update(onRename=True),
                "does not support 'onRename'",
            ),
            (
                "settings",
                lambda s: s["config/naming"].update(bogus=1),
                "unknown setting 'bogus'",
            ),
            (
                "settings",
                lambda s: s.update({"config/bogus": {"a": 1}}),
                "settings config/bogus",
            ),
            (
                "qualityDefinitions",
                lambda s: s.update({"Bogus-9000p": s["HDTV-720p"]}),
                "'Bogus-9000p' does not exist",
            ),
            (
                "qualityProfiles",
                lambda s: s["Any"].update(bogus=1),
                "unknown key 'bogus'",
            ),
        ]
        for key, mutate, message in cases:
            with self.subTest(message):
                spec = self.spec()
                mutate(spec[key])
                out, error = self.apply_fails(spec)
                self.assertIn(message, out)
                self.assertIn("nothing written", error)
                self.assertEqual(self.fake.writes(), [])

    def test_implementation_clash_is_a_problem(self):
        self.adopted()
        spec = self.spec()
        spec["notifications"][0]["name"] = "Unmanaged hook"
        spec["notifications"][0]["id"] = None
        out, _ = self.apply_fails(spec)
        self.assertIn("exists with implementation Webhook (want Telegram)", out)

    def test_duplicate_declared_names_are_a_problem(self):
        spec = self.spec()
        spec["notifications"].append(copy.deepcopy(spec["notifications"][0]))
        out, _ = self.apply_fails(spec)
        self.assertIn("declared names are not unique", out)

    # -- writes ------------------------------------------------------------

    def test_notifications_are_always_force_saved(self):
        self.apply()
        self.fake.stored("notification", 1)["onGrab"] = True
        self.apply()
        notification_writes = [
            r for r in self.fake.writes() if r[1].startswith("/notification")
        ]
        # create (POST, then the events by PUT) and one update
        self.assertEqual(len(notification_writes), 3)
        for write in notification_writes:
            self.assertEqual(write[2], {"forceSave": ["true"]})
        self.assertEqual([k for k, _ in self.fake.tests_run], ["downloadclient"])

    def test_settings_are_written_to_their_id(self):
        self.fake.settings["delayprofile/1"]["preferredProtocol"] = "torrent"
        self.apply()
        paths = [r[1] for r in self.fake.writes()]
        self.assertIn("/config/naming/1", paths)
        self.assertIn("/delayprofile/1", paths)
        self.assertNotIn("/delayprofile/1/1", paths)

    def test_backup_is_private_and_masked(self):
        self.adopted()
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.apply()
        (name,) = os.listdir(self.backups)
        path = os.path.join(self.backups, name)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        with open(path) as handle:
            text = handle.read()
        self.assertFalse(json.loads(text)["/config/naming"]["renameMovies"])
        for secret in [BOT_TOKEN, QBIT_PASSWORD, "synthetic-hook-password"]:
            self.assertNotIn(secret, text)

    def test_rate_limit_is_retried_after_retry_after(self):
        self.adopted()
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.fake.faults.append(
            {
                "method": "PUT",
                "path": "/config/naming/1",
                "kind": "429",
                "retryAfter": "7",
            }
        )
        self.apply()
        self.assertEqual(self.sleeps, [7.0])
        self.assertTrue(self.fake.settings["config/naming"]["renameMovies"])

    def test_retry_after_is_capped(self):
        self.adopted()
        self.fake.faults.append(
            {
                "method": "GET",
                "path": "/qualityprofile",
                "kind": "429",
                "retryAfter": "3600",
            }
        )
        self.apply()
        self.assertEqual(self.sleeps, [arr_sync.MAX_BACKOFF])

    def test_server_error_on_get_is_retried(self):
        self.fake.faults.append(
            {"method": "GET", "path": "/notification/schema", "kind": "500"}
        )
        self.apply()
        self.assertEqual(len(self.sleeps), 1)
        self.assertEqual(len(self.fake.providers["notification"]), 1)

    def test_uncertain_post_that_landed_is_not_repeated(self):
        self.fake.faults.append(
            {"method": "POST", "path": "/notification", "kind": "drop"}
        )
        out = self.apply()
        self.assertIn("the resource exists, so the create landed", out)
        self.assertEqual(len(self.fake.providers["notification"]), 1)
        posts = [r for r in self.fake.requests if r[:2] == ("POST", "/notification")]
        self.assertEqual(len(posts), 1)

    def test_uncertain_post_that_did_not_land_is_retried(self):
        self.fake.faults.append(
            {"method": "POST", "path": "/notification", "kind": "500"}
        )
        out = self.apply()
        self.assertIn("not created, retrying", out)
        self.assertEqual(len(self.fake.providers["notification"]), 1)
        posts = [r for r in self.fake.requests if r[:2] == ("POST", "/notification")]
        self.assertEqual(len(posts), 2)

    def test_partial_failure_reports_progress_and_next_run_finishes(self):
        self.adopted()
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.fake.settings["config/mediamanagement"][
            "minimumFreeSpaceWhenImporting"
        ] = 1
        spec = self.spec()
        # a validation error on the second write, echoing the attempted value
        self.fake.faults.append(
            {"method": "PUT", "path": "/config/mediamanagement/1", "kind": "500"}
        )
        for _ in range(arr_sync.RETRIES):
            self.fake.faults.append(
                {"method": "PUT", "path": "/config/mediamanagement/1", "kind": "500"}
            )
        out, error = self.apply_fails(spec)
        self.assertIn("1 write(s) done, not done: update config/mediamanagement", error)
        self.assertTrue(self.fake.settings["config/naming"]["renameMovies"])
        self.assertIn("converged, 1 write(s)", self.apply(spec))
        self.assertIn("converged, 0 write(s)", self.apply(spec))

    def test_notification_is_created_without_a_test_message(self):
        self.apply()
        created = [r for r in self.fake.writes() if r[1].startswith("/notification")]
        self.assertEqual(
            [(r[0], r[1]) for r in created],
            [("POST", "/notification"), ("PUT", "/notification/1")],
        )
        self.assertEqual(self.fake.tests_run, [("downloadclient", "qBittorrent")])
        tg = self.fake.stored("notification", 1)
        self.assertTrue(tg["onUpgrade"] and tg["onMovieDelete"])

    def test_uncertain_post_giving_up_reports_progress(self):
        for _ in range(arr_sync.RETRIES + 1):
            self.fake.faults.append(
                {"method": "POST", "path": "/notification", "kind": "500"}
            )
        out, error = self.apply_fails()
        self.assertIn("not created after 6 attempts", error)
        self.assertIn(
            "write(s) done, not done: create notification 'Telegram Group'", error
        )
        self.assertEqual(self.fake.providers["notification"], [])

    def test_garbled_get_is_retried(self):
        self.fake.faults.append(
            {"method": "GET", "path": "/notification", "kind": "garbled"}
        )
        self.apply()
        self.assertEqual(len(self.sleeps), 1)

    def test_garbled_post_response_is_looked_up(self):
        self.fake.faults.append(
            {"method": "POST", "path": "/notification", "kind": "garbled"}
        )
        out = self.apply()
        self.assertIn("the resource exists, so the create landed", out)
        self.assertEqual(len(self.fake.providers["notification"]), 1)

    def test_unparsable_retry_after_backs_off(self):
        self.assertEqual(arr_sync.retry_delay(2, "soon"), 4)
        self.assertEqual(arr_sync.retry_delay(0, "3"), 3)

    def test_two_specs_claiming_one_resource_is_a_problem(self):
        self.adopted()
        spec = self.spec()
        other = copy.deepcopy(spec["notifications"][0])
        other["name"] = "Another name"
        spec["notifications"].append(other)
        out, _ = self.apply_fails(spec)
        self.assertIn("notification id 2 is matched by both", out)
        self.assertEqual(self.fake.writes(), [])

    def test_wrong_api_key_fails_fast(self):
        with self.assertRaises(SystemExit) as caught:
            arr_sync.wait_ready("radarr", self.spec()["url"], "v3", "wrong-key")
        self.assertIn("HTTP 401", str(caught.exception))

    def test_validation_error_hides_attempted_values(self):
        self.adopted()
        spec = self.spec()
        spec["notifications"][0]["name"] = ""
        spec["notifications"][0]["id"] = 2
        out, error = self.apply_fails(spec)
        self.assertIn("Name: Name must not be empty", error)
        self.assertNotIn("attemptedValue", error)

    def test_read_only_api_refuses_writes(self):
        api = arr_sync.ReadOnlyApi(self.spec()["url"], "v3", "synthetic-api-key")
        for method in ("POST", "PUT", "DELETE"):
            with self.assertRaises(RuntimeError):
                api.request(method, "/notification/1", {})
        self.assertEqual(self.fake.requests, [])

    def test_preview_reports_changes_and_never_writes(self):
        rc, out = self.preview(expect_no_changes=False)
        self.assertEqual(rc, 0, out)
        self.assertIn("would create notification 'Telegram Group'", out)
        rc, _ = self.preview(expect_no_changes=True)
        self.assertEqual(rc, 1)
        self.assertEqual(self.fake.writes(), [])


def set_field(resource, name, value):
    next(f for f in resource["fields"] if f["name"] == name)["value"] = value


def file_digest(path):
    digest = hashlib.sha256()
    for suffix in ("", "-wal"):
        if os.path.exists(path + suffix):
            with open(path + suffix, "rb") as handle:
                digest.update(handle.read())
    return digest.hexdigest()


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0], "-v"], exit=False).result
    sys.exit(0 if result.wasSuccessful() else 1)
