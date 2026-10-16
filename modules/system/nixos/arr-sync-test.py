"""Offline tests of arr-sync against a fake Servarr API.

The fake behaves like Radarr/Sonarr v3 where it matters: privacy fields are
masked as "********" in every response and a mask sent back keeps the stored
value; providers live in a WAL-mode SQLite database like the real one; the
create of an enabled provider runs Test() (forceSave or not), and so does a
changed update of one unless forceSave=true; like Radarr it syncs an import
list as soon as one is added or changed while enabled (recorded, so tests can
assert none happened), and validates a list's profile and root folder; the
host config keeps the login only when the password hash is echoed back;
validation errors echo attempted values. Faults (429 with
Retry-After, 5xx, a dropped connection after applying) can be injected.

usage: arr-sync-test.py <dir holding arr_sync.py>
"""

import base64
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
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, sys.argv.pop(1))
import arr_sync  # noqa: E402

MASK = "********"
BOT_TOKEN = "synthetic-bot-token-1"
OTHER_TOKEN = "synthetic-bot-token-2"
CHAT_ID = "-100000000001"
QBIT_PASSWORD = "synthetic-qbit-password"
PLEX_TOKEN = "synthetic-plex-token-1"
API_KEY = "synthetic-api-key"
PASSWORD_HASH = "synthetic-password-hash-base64="
SECRETS = [BOT_TOKEN, OTHER_TOKEN, CHAT_ID, QBIT_PASSWORD, PLEX_TOKEN]
# Radarr's and Sonarr's Users table, as their migrations leave it (from hoard's
# databases, 2026-10-16)
USERS_DDL = """
CREATE TABLE "Users" ("Id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "Identifier" TEXT NOT NULL, "Username" TEXT NOT NULL, "Password" TEXT NOT NULL,
  "Salt" TEXT, "Iterations" INTEGER);
CREATE UNIQUE INDEX "IX_Users_Identifier" ON "Users" ("Identifier" ASC);
CREATE UNIQUE INDEX "IX_Users_Username" ON "Users" ("Username" ASC);
"""
LOGIN_PASSWORD = "synthetic-login-password-1"


def synthetic_login(password=LOGIN_PASSWORD, username="admin"):
    """A login as Servarr's UserService stores it, for a synthetic password."""
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha512", password.encode(), salt, 10000, 32)
    return {
        "identifier": str(uuid.uuid4()),
        "username": username,
        "password": base64.b64encode(digest).decode(),
        "salt": base64.b64encode(salt).decode(),
        "iterations": 10000,
    }


def verifies(row, password):
    """Servarr's VerifyHashedPassword: whether a login accepts this password."""
    digest = hashlib.pbkdf2_hmac(
        "sha512",
        password.encode(),
        base64.b64decode(row["salt"]),
        row["iterations"],
        32,
    )
    return base64.b64encode(digest).decode() == row["password"]


TABLES = {
    "downloadclient": "DownloadClients",
    "notification": "Notifications",
    "importlist": "ImportLists",
    "metadata": "Metadata",
}


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


def plex_list_schema():
    # Radarr's: the token is a plain ("normal") field in the API
    return {
        "id": 0,
        "name": "",
        "implementation": "PlexImport",
        "configContract": "PlexListSettings",
        "enabled": False,
        "enableAuto": True,
        "monitor": "movieOnly",
        "searchOnAdd": True,
        "minimumAvailability": "released",
        "qualityProfileId": 0,
        "rootFolderPath": "",
        "listType": "plex",
        "listOrder": 3,
        "minRefreshInterval": "06:00:00",
        "tags": [],
        "fields": [field("accessToken", ""), field("signIn", "startOAuth")],
    }


def sonarr_list_schema():
    return {
        "id": 0,
        "name": "",
        "implementation": "PlexImport",
        "configContract": "PlexListSettings",
        "enableAutomaticAdd": True,
        "searchForMissingEpisodes": True,
        "shouldMonitor": "all",
        "qualityProfileId": 0,
        "rootFolderPath": "",
        "tags": [],
        "fields": [field("accessToken", "")],
    }


def kodi_metadata(resource_id=1):
    return {
        "id": resource_id,
        "name": "Kodi (XBMC) / Emby",
        "implementation": "XbmcMetadata",
        "configContract": "XbmcMetadataSettings",
        "enable": False,
        "tags": [],
        "fields": [field("movieMetadata", True), field("movieImages", True)],
    }


def default_host():
    return {
        "id": 1,
        "bindAddress": "*",
        "port": 7878,
        "apiKey": API_KEY,
        "username": "admin",
        "password": PASSWORD_HASH,
        "passwordConfirmation": "",
        "logLevel": "debug",
        "instanceName": "Radarr",
        "proxyPassword": "",
        "backupRetention": 7,
        # not mapped by Servarr's resource: always answers false
        "trustCgnatIpAddresses": False,
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
            "importlist": [plex_list_schema()],
            "metadata": [kodi_metadata(0)],
        }
        self.providers = {kind: [] for kind in TABLES}
        self.settings = default_settings()
        self.host = default_host()
        self.quality_definitions = default_quality_definitions()
        self.profiles = default_profiles()
        self.rootfolders = []
        self.tags = []
        self.custom_filters = []
        self.next_id = {kind: 1 for kind in TABLES}
        self.requests = []
        self.tests_run = []
        # list syncs Radarr starts on its own when a list is added or changed
        self.list_syncs = []
        self.faults = []
        # makes the list validator quote a field's value, as URL validators do
        self.quote_in_errors = None
        self.lock = threading.Lock()
        con = sqlite3.connect(db_path, check_same_thread=False)
        con.execute("PRAGMA journal_mode=WAL")
        for table in TABLES.values():
            con.execute(
                f"CREATE TABLE {table} (Id INTEGER PRIMARY KEY, Name TEXT, Settings TEXT)"
            )
        con.executescript(USERS_DDL)
        con.commit()
        # the app keeps its connection open, which keeps the -wal/-shm files
        self.con = con

    def set_login(self, login):
        """The app's login: its Users row, and the hash config/host returns."""
        self.con.execute("DELETE FROM Users")
        self.con.execute(
            "INSERT INTO Users (Identifier, Username, Password, Salt, Iterations) "
            "VALUES (?, ?, ?, ?, ?)",
            [login[key] for key in arr_sync.LOGIN_COLUMNS],
        )
        self.con.commit()
        self.host.update(username=login["username"], password=login["password"])

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
        if kind in ("downloadclient", "metadata"):
            return resource.get("enable", False)
        if kind == "importlist":
            # Radarr's Enabled, Sonarr's EnableAutomaticAdd
            return resource.get("enabled", resource.get("enableAutomaticAdd", False))
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

    def validate_list(self, resource):
        """Radarr's list validators: an existing profile and root folder."""
        errors = []
        if self.quote_in_errors:
            value = next(
                f["value"]
                for f in resource["fields"]
                if f["name"] == self.quote_in_errors
            )
            errors.append(
                {"propertyName": "Url", "errorMessage": f"Invalid Url: '{value}'"}
            )
        if resource["qualityProfileId"] not in [p["id"] for p in self.profiles]:
            errors.append(
                {"propertyName": "QualityProfileId", "errorMessage": "missing"}
            )
        roots = [rf["path"] for rf in self.rootfolders]
        if resource["rootFolderPath"] not in roots:
            errors.append({"propertyName": "RootFolderPath", "errorMessage": "missing"})
        return errors

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
            if path == "/config/host":
                return 200, self.host
            if path == "/tag":
                return 200, self.tags
            if path == "/customfilter":
                return 200, self.custom_filters
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
                if kind == "importlist":
                    errors = self.validate_list(body)
                    if errors:
                        return 400, errors
                # Servarr tests every enabled provider it creates, forceSave or not
                if self.enabled(kind, body):
                    self.tests_run.append((kind, body["name"]))
                created = self.add(kind, self.merge_fields({}, body))
                # Radarr syncs an added list at once, unless it is disabled
                if kind == "importlist" and self.enabled(kind, created):
                    self.list_syncs.append(created["name"])
                return 201, self.masked(created)
            if method == "PUT" and len(rest) == 1:
                old = self.stored(kind, int(rest[0]))
                new = self.merge_fields(old, body)
                new["id"] = old["id"]
                if kind == "importlist":
                    errors = self.validate_list(new)
                    if errors:
                        return 400, errors
                if self.enabled(kind, new) and not force and new != old:
                    self.tests_run.append((kind, new["name"]))
                # ... and a changed one
                if kind == "importlist" and self.enabled(kind, new) and new != old:
                    self.list_syncs.append(new["name"])
                self.providers[kind][self.providers[kind].index(old)] = new
                self.store(kind, new)
                return 202, self.masked(new)
        if kind == "tag" and method == "POST" and not rest:
            existing = next((t for t in self.tags if t["label"] == body["label"]), None)
            if existing:
                return 201, existing
            tag = {"id": max([t["id"] for t in self.tags], default=0) + 1}
            tag["label"] = body["label"].lower()
            self.tags.append(tag)
            return 201, tag
        if kind == "customfilter" and method == "POST" and not rest:
            created = dict(
                body, id=max([f["id"] for f in self.custom_filters], default=0) + 1
            )
            self.custom_filters.append(created)
            return 201, created
        if kind == "customfilter" and method == "PUT" and len(rest) == 1:
            index = next(
                i for i, f in enumerate(self.custom_filters) if f["id"] == int(rest[0])
            )
            self.custom_filters[index] = dict(body, id=int(rest[0]))
            return 202, self.custom_filters[index]
        if path == "/config/host/1" and method == "PUT":
            # UserService.Upsert re-hashes only a password differing from the hash
            if body["password"] != self.host["password"]:
                body["password"] = "rehashed:" + body["password"]
            self.host = body
            return 202, body
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
        self.assertIn("field botToken can't be checked against the database", out)
        self.apply_fails(spec)
        self.assertEqual(self.fake.writes(), [])

    def test_unreadable_database_is_unverifiable_not_fatal(self):
        self.adopted()
        spec = self.spec(database=os.path.join(self.dir, "missing.db"))
        rc, out = self.preview(spec)
        self.assertEqual(rc, 1)
        self.assertIn("can't be checked against the database", out)

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

    # -- import lists, tags, metadata, custom filters, host ------------------

    def full_spec(self, **overrides):
        """The spec plus everything added for completeness, as on hoard."""
        path = os.path.join(self.dir, "plex-token")
        with open(path, "w") as handle:
            handle.write(PLEX_TOKEN + "\n")
        spec = self.spec(
            importLists=[
                {
                    "id": 1,
                    "name": "Plex Watchlist",
                    "implementation": "PlexImport",
                    "properties": {
                        "enabled": False,
                        "enableAuto": False,
                        "monitor": "movieOnly",
                        "searchOnAdd": True,
                        "minimumAvailability": "released",
                        "rootFolderPath": "/media/movies",
                    },
                    "qualityProfile": "Any",
                    "tagLabels": ["my-plex-watchlist"],
                    "fields": {"signIn": "startOAuth"},
                    "secretFields": {"accessToken": path},
                },
                {
                    "id": 3,
                    "name": "Person",
                    "implementation": "PlexImport",
                    "properties": {
                        "enabled": True,
                        "enableAuto": True,
                        "monitor": "movieOnly",
                        "searchOnAdd": True,
                        "minimumAvailability": "released",
                        "rootFolderPath": "/media/movies",
                    },
                    "qualityProfile": "Any",
                    "tagLabels": ["1-someone"],
                    "fields": {"signIn": "startOAuth"},
                    "secretFields": {},
                },
            ],
            metadata=[
                {
                    "id": 1,
                    "name": "Kodi (XBMC) / Emby",
                    "implementation": "XbmcMetadata",
                    "properties": {"enable": False, "tags": []},
                    "fields": {"movieMetadata": True, "movieImages": True},
                    "secretFields": {},
                }
            ],
            customFilters=[
                {
                    "id": 2,
                    "type": "movieIndex",
                    "label": "misc",
                    "filters": [
                        {"key": "path", "type": "contains", "value": ["/misc/"]}
                    ],
                }
            ],
        )
        spec["settings"]["config/host"] = {
            "bindAddress": "*",
            "logLevel": "debug",
            "instanceName": "Radarr",
            "proxyPassword": "",
            "backupRetention": 7,
        }
        spec.update(overrides)
        return spec

    def adopted_full(self):
        self.adopted()
        self.fake.tags.extend(
            [
                {"id": 2, "label": "my-plex-watchlist"},
                {"id": 4, "label": "1-someone"},
                # Seerr's tag for another user: never touched
                {"id": 7, "label": "3-other"},
            ]
        )
        plex = plex_list_schema()
        plex.update(
            id=1,
            name="Plex Watchlist",
            enabled=False,
            enableAuto=False,
            qualityProfileId=5,
            rootFolderPath="/media/movies",
            tags=[2],
        )
        set_field(plex, "accessToken", PLEX_TOKEN)
        self.fake.add("importlist", plex)
        person = plex_list_schema()
        person.update(
            id=3,
            name="Person",
            enabled=True,
            enableAuto=True,
            qualityProfileId=5,
            rootFolderPath="/media/movies",
            tags=[4],
        )
        self.fake.add("importlist", person)
        self.fake.add("metadata", kodi_metadata())
        self.fake.custom_filters.append(
            {
                "id": 2,
                "type": "movieIndex",
                "label": "misc",
                "filters": [{"key": "path", "type": "contains", "value": ["/misc/"]}],
            }
        )

    def test_full_adoption_writes_nothing_and_syncs_no_list(self):
        self.adopted_full()
        db_before = file_digest(self.fake.db_path)
        host_before = copy.deepcopy(self.fake.host)
        rc, out = self.preview(self.full_spec())
        self.assertEqual(rc, 0, out)
        self.assertIn(
            "0 write(s), 0 problem(s), 0 mismatch(es), 0 unverifiable, 0 held", out
        )
        out = self.apply(self.full_spec())
        self.assertIn("converged, 0 write(s)", out)
        self.assertEqual(self.fake.writes(), [])
        self.assertEqual(self.fake.list_syncs, [])
        self.assertEqual(self.fake.tests_run, [])
        self.assertEqual(file_digest(self.fake.db_path), db_before)
        self.assertEqual(self.fake.host, host_before)
        self.assertEqual(os.listdir(self.backups), [])

    def test_fresh_install_creates_lists_switched_off_without_a_sync(self):
        rc, out = self.preview(self.full_spec(), expect_no_changes=False)
        self.assertIn("would create tag 'my-plex-watchlist'", out)
        self.assertEqual(self.fake.writes(), [])
        out, error = self.apply_fails(self.full_spec())
        self.assertIn("import list changes held", error)
        self.assertIn("HELD importlist 'Person': created switched off", out)
        lists = {l["name"]: l for l in self.fake.providers["importlist"]}
        # created with this install's ids for the profile and the tags
        labels = {t["id"]: t["label"] for t in self.fake.tags}
        self.assertEqual(
            [labels[i] for i in lists["Plex Watchlist"]["tags"]], ["my-plex-watchlist"]
        )
        self.assertEqual([labels[i] for i in lists["Person"]["tags"]], ["1-someone"])
        self.assertEqual(lists["Person"]["qualityProfileId"], 5)
        self.assertEqual(
            self.fake.field_value(
                "importlist", lists["Plex Watchlist"]["id"], "accessToken"
            ),
            PLEX_TOKEN,
        )
        # nothing enabled, so no test fetch and no sync
        self.assertFalse(lists["Person"]["enabled"] or lists["Person"]["enableAuto"])
        self.assertEqual(self.fake.list_syncs, [])
        self.assertNotIn("importlist", [k for k, _ in self.fake.tests_run])
        # the disabled list took one write, no forceSave update after it
        list_writes = [r for r in self.fake.writes() if r[1].startswith("/importlist")]
        self.assertEqual([r[0] for r in list_writes], ["POST", "POST"])
        # the root folder exists before the lists that point at it
        paths = [r[1] for r in self.fake.writes()]
        self.assertLess(paths.index("/rootfolder"), paths.index("/importlist"))
        # switched on in the UI: from then on nothing is held or written
        lists["Person"].update(enabled=True, enableAuto=True)
        before = len(self.fake.writes())
        out = self.apply(self.full_spec())
        self.assertIn("converged, 0 write(s)", out)
        self.assertEqual(len(self.fake.writes()), before)

    def test_change_to_an_enabled_list_is_held_not_written(self):
        self.adopted_full()
        self.fake.stored("importlist", 3)["searchOnAdd"] = False
        rc, out = self.preview(self.full_spec())
        self.assertEqual(rc, 1)
        self.assertIn("HELD importlist 'Person' (id 3): searchOnAdd not written", out)
        out, error = self.apply_fails(self.full_spec())
        self.assertEqual(self.fake.writes(), [])
        self.assertEqual(self.fake.list_syncs, [])
        self.assertFalse(self.fake.stored("importlist", 3)["searchOnAdd"])

    def test_disabled_list_is_kept_disabled_without_a_sync(self):
        self.adopted_full()
        plex = self.fake.stored("importlist", 1)
        plex["minimumAvailability"] = "announced"
        self.apply(self.full_spec())
        self.assertEqual(
            [(r[0], r[1]) for r in self.fake.writes()], [("PUT", "/importlist/1")]
        )
        self.assertEqual(self.fake.writes()[0][2], {"forceSave": ["true"]})
        self.assertEqual(
            self.fake.stored("importlist", 1)["minimumAvailability"], "released"
        )
        self.assertFalse(self.fake.stored("importlist", 1)["enabled"])
        self.assertEqual(self.fake.list_syncs, [])

    def test_enabling_a_disabled_list_is_held(self):
        self.adopted_full()
        spec = self.full_spec()
        spec["importLists"][0]["properties"]["enabled"] = True
        out, _ = self.apply_fails(spec)
        self.assertIn(
            "HELD importlist 'Plex Watchlist' (id 1): enabled not written", out
        )
        self.assertFalse(self.fake.stored("importlist", 1)["enabled"])
        self.assertEqual(self.fake.list_syncs, [])

    def test_list_token_differing_from_sops_is_kept(self):
        self.adopted_full()
        plex = self.fake.stored("importlist", 1)
        set_field(plex, "accessToken", "synthetic-plex-token-other")
        self.fake.store("importlist", plex)
        rc, out = self.preview(self.full_spec())
        self.assertEqual(rc, 1)
        self.assertIn(
            "field accessToken differs from its secret file; live value kept", out
        )
        self.apply_fails(self.full_spec())
        self.assertEqual(
            self.fake.field_value("importlist", 1, "accessToken"),
            "synthetic-plex-token-other",
        )

    def test_list_without_its_profile_yet_is_skipped(self):
        self.fake.profiles.clear()
        out = self.apply(self.full_spec(qualityProfiles={}))
        self.assertIn("quality profile 'Any' does not exist yet; skipped", out)
        self.assertEqual(self.fake.providers["importlist"], [])

    def test_tag_order_does_not_matter_and_tags_are_never_removed(self):
        self.adopted_full()
        spec = self.full_spec()
        self.fake.stored("importlist", 1)["tags"] = [7, 2]
        spec["importLists"][0]["tagLabels"] = ["my-plex-watchlist", "3-other"]
        self.apply(spec)
        self.assertEqual(self.fake.writes(), [])
        # the declared set is the whole set: an extra tag on the list goes
        self.fake.stored("importlist", 1)["tags"] = [2, 7, 4]
        self.apply(spec)
        self.assertEqual(sorted(self.fake.stored("importlist", 1)["tags"]), [2, 7])
        self.assertIn({"id": 7, "label": "3-other"}, self.fake.tags)
        self.assertFalse(any(r[0] == "DELETE" for r in self.fake.requests))

    def test_uppercase_tag_label_is_a_problem(self):
        spec = self.full_spec()
        spec["importLists"][0]["tagLabels"] = ["My-Plex"]
        out, _ = self.apply_fails(spec)
        self.assertIn("tag labels must match [a-z0-9-]+", out)
        self.assertEqual(self.fake.writes(), [])
        # Seerr's older "<id> - <name>" form is rejected by Radarr: caught before writing
        spec["importLists"][0]["tagLabels"] = ["1 - someone"]
        out, _ = self.apply_fails(spec)
        self.assertIn("tag labels must match", out)
        self.assertEqual(self.fake.writes(), [])

    def test_held_list_creates_no_tag(self):
        self.adopted_full()
        self.fake.tags.remove({"id": 4, "label": "1-someone"})
        out, _ = self.apply_fails(self.full_spec())
        self.assertIn("HELD importlist 'Person' (id 3): tags not written", out)
        self.assertEqual(self.fake.writes(), [])
        self.assertNotIn("1-someone", [t["label"] for t in self.fake.tags])

    def test_disabling_an_enabled_list_is_written_without_a_sync(self):
        self.adopted_full()
        self.fake.stored("importlist", 1).update(enabled=True)
        self.apply(self.full_spec())
        self.assertEqual(
            [(r[0], r[1]) for r in self.fake.writes()], [("PUT", "/importlist/1")]
        )
        self.assertFalse(self.fake.stored("importlist", 1)["enabled"])
        self.assertEqual(self.fake.list_syncs, [])

    def test_disabled_list_gets_its_auto_add_by_a_second_write(self):
        spec = self.full_spec()
        spec["importLists"] = spec["importLists"][:1]
        spec["importLists"][0]["properties"]["enableAuto"] = True
        self.apply(spec)
        list_writes = [r for r in self.fake.writes() if r[1].startswith("/importlist")]
        self.assertEqual([r[0] for r in list_writes], ["POST", "PUT"])
        self.assertEqual(list_writes[1][2], {"forceSave": ["true"]})
        plex = self.fake.providers["importlist"][0]
        self.assertTrue(plex["enableAuto"] and not plex["enabled"])
        self.assertEqual(self.fake.list_syncs, [])
        self.assertEqual(self.fake.tests_run, [("downloadclient", "qBittorrent")])

    def test_sonarr_list_is_created_switched_off_and_held(self):
        self.fake.schemas["importlist"] = [sonarr_list_schema()]
        spec = self.full_spec()
        spec["importLists"] = [
            {
                "name": "Shows",
                "implementation": "PlexImport",
                "properties": {
                    "enableAutomaticAdd": True,
                    "rootFolderPath": "/media/movies",
                },
                "qualityProfile": "Any",
                "tagLabels": [],
                "fields": {},
                "secretFields": {},
            }
        ]
        out, _ = self.apply_fails(spec)
        self.assertIn("HELD importlist 'Shows': created switched off", out)
        self.assertFalse(self.fake.providers["importlist"][0]["enableAutomaticAdd"])
        self.assertEqual(self.fake.list_syncs, [])
        self.assertEqual(self.fake.tests_run, [("downloadclient", "qBittorrent")])

    def test_list_root_folder_must_exist_or_be_declared(self):
        spec = self.full_spec(rootFolders=[])
        out, _ = self.apply_fails(spec)
        self.assertIn("root folder /media/movies is not declared or present", out)
        self.assertEqual(self.fake.writes(), [])

    def test_secret_quoted_in_an_error_message_is_scrubbed(self):
        self.fake.quote_in_errors = "accessToken"
        spec = self.full_spec()
        spec["importLists"] = spec["importLists"][:1]
        out, error = self.apply_fails(spec)
        self.assertIn("Invalid Url: '<redacted>'", error)
        self.assertNotIn(PLEX_TOKEN, out + error)

    def test_uncertain_tag_create_that_landed_is_not_repeated(self):
        self.fake.faults.append({"method": "POST", "path": "/tag", "kind": "drop"})
        spec = self.full_spec()
        spec["importLists"] = spec["importLists"][:1]
        self.apply(spec)
        self.assertEqual([t["label"] for t in self.fake.tags], ["my-plex-watchlist"])

    def test_metadata_consumer_is_kept_off(self):
        self.adopted_full()
        self.fake.stored("metadata", 1)["enable"] = True
        self.apply(self.full_spec())
        self.assertEqual(
            [(r[0], r[1]) for r in self.fake.writes()], [("PUT", "/metadata/1")]
        )
        self.assertFalse(self.fake.stored("metadata", 1)["enable"])

    def test_custom_filter_rename_is_undone_by_id(self):
        self.adopted_full()
        self.fake.custom_filters[0]["label"] = "renamed"
        self.apply(self.full_spec())
        self.assertEqual(
            [(r[0], r[1]) for r in self.fake.writes()], [("PUT", "/customfilter/2")]
        )
        self.assertEqual(self.fake.custom_filters[0]["label"], "misc")
        self.assertEqual(len(self.fake.custom_filters), 1)

    def test_custom_filter_matches_by_type_and_label_after_reinstall(self):
        self.adopted_full()
        spec = self.full_spec()
        spec["customFilters"][0]["id"] = 9
        rc, out = self.preview(spec)
        self.assertEqual(rc, 0, out)

    def test_custom_filter_id_of_another_list_type_is_not_taken(self):
        self.adopted_full()
        self.fake.custom_filters.append(
            {"id": 5, "type": "queue", "label": "q", "filters": []}
        )
        spec = self.full_spec()
        spec["customFilters"][0].update(id=5)
        rc, out = self.preview(spec)
        self.assertEqual(rc, 0, out)
        spec["customFilters"][0].update(label="new one")
        self.apply(spec)
        self.assertEqual(
            [(r[0], r[1]) for r in self.fake.writes()], [("POST", "/customfilter")]
        )
        self.assertEqual(self.fake.custom_filters[1]["label"], "q")

    def test_duplicate_custom_filters_are_a_problem(self):
        spec = self.full_spec()
        spec["customFilters"].append(copy.deepcopy(spec["customFilters"][0]))
        out, _ = self.apply_fails(spec)
        self.assertIn("declared type + label are not unique", out)

    def test_host_change_keeps_the_login(self):
        self.adopted_full()
        self.fake.host["logLevel"] = "info"
        self.apply(self.full_spec())
        self.assertEqual([r[1] for r in self.fake.writes()], ["/config/host/1"])
        self.assertEqual(self.fake.host["logLevel"], "debug")
        # the hash went back unchanged, so the password wasn't re-hashed
        self.assertEqual(self.fake.host["password"], PASSWORD_HASH)
        self.assertEqual(self.fake.host["apiKey"], API_KEY)

    def test_host_credentials_cant_be_declared(self):
        for key, value in (
            ("apiKey", "x"),
            ("username", "admin"),
            ("password", "x"),
            ("proxyPassword", "x"),
        ):
            spec = self.full_spec()
            spec["settings"]["config/host"][key] = value
            out, _ = self.apply_fails(spec)
            self.assertIn(f"'{key}' is a credential", out)
        self.assertEqual(self.fake.writes(), [])

    def test_backup_redacts_host_credentials_and_list_token(self):
        self.adopted_full()
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.apply(self.full_spec())
        (name,) = os.listdir(self.backups)
        with open(os.path.join(self.backups, name)) as handle:
            text = handle.read()
        for secret in [PLEX_TOKEN, API_KEY, PASSWORD_HASH, QBIT_PASSWORD, BOT_TOKEN]:
            self.assertNotIn(secret, text)
        backup = json.loads(text)
        self.assertEqual(backup["/config/host"]["apiKey"], "<redacted>")
        self.assertEqual(backup["/config/naming"]["renameMovies"], False)
        self.assertEqual(backup["/config/host"]["username"], "<redacted>")

    def test_backup_redacts_a_live_secret_differing_from_sops(self):
        self.adopted_full()
        plex = self.fake.stored("importlist", 1)
        set_field(plex, "accessToken", "synthetic-live-token-differs")
        self.fake.store("importlist", plex)
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.apply_fails(self.full_spec())
        (name,) = os.listdir(self.backups)
        with open(os.path.join(self.backups, name)) as handle:
            text = handle.read()
        self.assertNotIn("synthetic-live-token-differs", text)

    def test_secret_inside_a_longer_string_is_redacted(self):
        secrets = {"synthetic-feed-id-123"}
        self.assertEqual(
            arr_sync.redacted(
                {"url": "https://rss.example/synthetic-feed-id-123"}, secrets
            ),
            {"url": "<redacted>"},
        )
        # a short secret only as the whole value
        self.assertEqual(
            arr_sync.redacted({"user": "admin-x"}, {"admin"}), {"user": "admin-x"}
        )

    def test_preview_reports_changes_and_never_writes(self):
        rc, out = self.preview(expect_no_changes=False)
        self.assertEqual(rc, 0, out)
        self.assertIn("would create notification 'Telegram Group'", out)
        rc, _ = self.preview(expect_no_changes=True)
        self.assertEqual(rc, 1)
        self.assertEqual(self.fake.writes(), [])

    # -- the login ---------------------------------------------------------

    def login_spec(self, login):
        path = os.path.join(self.dir, "login")
        with open(path, "w") as handle:
            json.dump(login, handle)
        return self.full_spec(login=path)

    def assertNoLogin(self, text, *logins):
        for login in logins:
            for key in ("identifier", "password", "salt"):
                self.assertNotIn(login[key], text)

    def test_login_equal_to_its_secret_writes_nothing(self):
        self.adopted_full()
        login = synthetic_login()
        self.fake.set_login(login)
        rc, out = self.preview(self.login_spec(login))
        self.assertEqual(rc, 0, out)
        self.assertIn("login matches its secret", out)
        self.assertIn("0 write(s), 0 problem(s), 0 mismatch(es)", out)
        self.assertNoLogin(out, login)
        self.apply(self.login_spec(login))
        self.assertEqual(self.fake.writes(), [])

    def test_differing_login_is_kept_and_its_hash_never_sent(self):
        # the double-hash regression: a host write echoes the live hash, never
        # the secret's, which the app would hash again as a plaintext password
        self.adopted_full()
        live, other = synthetic_login(), synthetic_login("synthetic-other-password")
        self.fake.set_login(live)
        self.fake.host["logLevel"] = "info"
        out, err = self.apply_fails(self.login_spec(other))
        self.assertIn(
            "login (identifier, password, salt) differs from its secret file", out
        )
        self.assertIn("secrets differ", err)
        self.assertEqual([r[1] for r in self.fake.writes()], ["/config/host/1"])
        self.assertEqual(self.fake.host["password"], live["password"])
        (row,) = arr_sync.login_rows(self.fake.con)
        self.assertEqual(row, live)
        self.assertNoLogin(out + err, live, other)

    def test_login_changed_after_planning_is_not_sent_back(self):
        # a password changed in the UI between planning and the host write:
        # echoing the planned hash would make it the new plaintext password
        self.adopted_full()
        login = synthetic_login()
        self.fake.set_login(login)
        self.fake.host["logLevel"] = "info"
        changed = synthetic_login("synthetic-new-ui-password")
        real = arr_sync.with_tag_ids

        def ui_change(api, write):
            self.fake.host["password"] = changed["password"]
            return real(api, write)

        with unittest.mock.patch.object(arr_sync, "with_tag_ids", ui_change):
            _, err = self.apply_fails(self.login_spec(login))
        self.assertIn("the login changed since planning", err)
        self.assertEqual(self.fake.writes(), [])
        self.assertEqual(self.fake.host["password"], changed["password"])
        self.assertNoLogin(err, login, changed)

    def test_unreadable_database_leaves_the_login_unverifiable(self):
        self.adopted_full()
        login = synthetic_login()
        self.fake.set_login(login)
        broken = os.path.join(self.dir, "broken.db")
        with open(broken, "w") as handle:
            handle.write("not a database\n" * 100)
        spec = self.login_spec(login)
        rc, out = self.preview(dict(spec, database=broken))
        self.assertEqual(rc, 1)
        self.assertIn("cannot read the login from the database", out)
        self.assertIn("radarr: login can't be checked against the database", out)

    def test_app_without_a_login_gets_no_writes(self):
        self.adopted_full()
        self.fake.host.update(username="", password="")
        self.fake.settings["config/naming"]["renameMovies"] = False
        out, err = self.apply_fails(self.login_spec(synthetic_login()))
        self.assertIn("login: the app has none yet", out)
        self.assertIn("nothing written", err)
        self.assertEqual(self.fake.writes(), [])

    def test_bad_login_secret_is_a_problem(self):
        self.adopted_full()
        login = synthetic_login()
        self.fake.set_login(login)
        out, _ = self.apply_fails(self.login_spec(dict(login, password=LOGIN_PASSWORD)))
        self.assertIn("'password' is not 32 bytes of base64", out)
        self.assertNotIn(LOGIN_PASSWORD, out)
        self.assertEqual(self.fake.writes(), [])

    def test_backup_redacts_the_login(self):
        self.adopted_full()
        login = synthetic_login()
        self.fake.set_login(login)
        self.fake.settings["config/naming"]["renameMovies"] = False
        self.apply(self.login_spec(login))
        (name,) = os.listdir(self.backups)
        with open(os.path.join(self.backups, name)) as handle:
            text = handle.read()
        self.assertNoLogin(text, login)
        self.assertEqual(json.loads(text)["/config/host"]["username"], "<redacted>")


class RestoreLoginTest(unittest.TestCase):
    """restore_login against a database shaped like the app's (WAL, real Users)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "radarr.db")
        con = sqlite3.connect(self.db)
        con.execute("PRAGMA journal_mode=WAL")
        con.executescript(USERS_DDL)
        # stands for the library and history, which must stay untouched
        con.execute("CREATE TABLE History (Id INTEGER PRIMARY KEY, Data TEXT)")
        con.executemany(
            "INSERT INTO History (Data) VALUES (?)",
            [(f"event {n}",) for n in range(50)],
        )
        con.commit()
        con.close()
        self.login = synthetic_login()
        self.secret = self.write_secret(self.login)

    def tearDown(self):
        self.tmp.cleanup()

    def write_secret(self, value, name="login"):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w") as handle:
            handle.write(value if isinstance(value, str) else json.dumps(value))
        return path

    def restore(self, secret=None):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            arr_sync.restore_login(self.db, secret or self.secret)
        self.assertNoLogin(out.getvalue())
        return out.getvalue()

    def restore_fails(self, secret=None):
        out = io.StringIO()
        with (
            contextlib.redirect_stdout(out),
            self.assertRaises((SystemExit, ValueError)) as caught,
        ):
            arr_sync.restore_login(self.db, secret or self.secret)
        self.assertNoLogin(out.getvalue() + str(caught.exception))
        return str(caught.exception)

    def assertNoLogin(self, text):
        for key in ("identifier", "password", "salt"):
            self.assertNotIn(self.login[key], text)
        self.assertNotIn(LOGIN_PASSWORD, text)

    def rows(self):
        con = sqlite3.connect(self.db)
        try:
            return arr_sync.login_rows(con)
        finally:
            con.close()

    def history(self):
        con = sqlite3.connect(self.db)
        try:
            return con.execute("SELECT * FROM History ORDER BY Id").fetchall()
        finally:
            con.close()

    def insert(self, login):
        con = sqlite3.connect(self.db)
        con.execute(
            "INSERT INTO Users (Identifier, Username, Password, Salt, Iterations) "
            "VALUES (?, ?, ?, ?, ?)",
            [login[key] for key in arr_sync.LOGIN_COLUMNS],
        )
        con.commit()
        con.close()

    def test_fresh_install_gets_the_login_and_only_that(self):
        history = self.history()
        out = self.restore()
        self.assertIn("login 'admin' restored", out)
        (row,) = self.rows()
        self.assertEqual(row, self.login)
        # the app's check: the original password logs in, nothing else does
        self.assertTrue(verifies(row, LOGIN_PASSWORD))
        self.assertFalse(verifies(row, "synthetic-wrong-password"))
        self.assertFalse(verifies(row, self.login["password"]))
        self.assertEqual(self.history(), history)
        con = sqlite3.connect(self.db)
        self.assertEqual(con.execute("PRAGMA integrity_check").fetchone(), ("ok",))
        self.assertEqual(con.execute("PRAGMA journal_mode").fetchone(), ("wal",))
        con.close()

    def test_second_run_changes_nothing(self):
        self.restore()
        before = file_digest(self.db)
        out = self.restore()
        self.assertIn("login matches its secret; nothing written", out)
        self.assertEqual(file_digest(self.db), before)

    def test_wal_left_by_the_app_is_not_checkpointed(self):
        # an app stopped without checkpointing leaves its -wal (Sonarr does):
        # a run with nothing to write must leave every file as it is
        self.restore()
        app = sqlite3.connect(self.db)
        app.execute("PRAGMA wal_autocheckpoint=0")
        app.execute("INSERT INTO History (Data) VALUES ('after the restore')")
        app.commit()
        stopped = os.path.join(self.tmp.name, "stopped")
        os.mkdir(stopped)
        for suffix in ("", "-wal", "-shm"):
            with (
                open(self.db + suffix, "rb") as src,
                open(os.path.join(stopped, "radarr.db" + suffix), "wb") as dst,
            ):
                dst.write(src.read())
        app.close()
        self.db = os.path.join(stopped, "radarr.db")
        self.assertGreater(os.path.getsize(self.db + "-wal"), 0)
        before = file_digest(self.db)
        self.assertIn("nothing written", self.restore())
        self.assertEqual(file_digest(self.db), before)
        other = self.write_secret(synthetic_login("synthetic-other-password"), "other")
        self.assertIn("left as is", self.restore_fails(other))
        self.assertEqual(file_digest(self.db), before)

    def test_differing_login_is_never_overwritten(self):
        other = synthetic_login("synthetic-other-password")
        self.insert(other)
        before = file_digest(self.db)
        err = self.restore_fails()
        self.assertIn("differing from the secret (identifier, password, salt)", err)
        self.assertEqual(self.rows(), [other])
        self.assertEqual(file_digest(self.db), before)
        for key in ("identifier", "password", "salt"):
            self.assertNotIn(other[key], err)

    def test_restore_beside_a_wal_left_by_the_app(self):
        # the app stopped with frames still in its -wal: they survive the insert
        app = sqlite3.connect(self.db)
        app.execute("PRAGMA wal_autocheckpoint=0")
        app.execute("INSERT INTO History (Data) VALUES ('in the wal')")
        app.commit()
        stopped = os.path.join(self.tmp.name, "stopped")
        os.mkdir(stopped)
        for suffix in ("", "-wal", "-shm"):
            with (
                open(self.db + suffix, "rb") as src,
                open(os.path.join(stopped, "radarr.db" + suffix), "wb") as dst,
            ):
                dst.write(src.read())
        history = self.history()
        app.close()
        self.db = os.path.join(stopped, "radarr.db")
        self.assertIn("restored", self.restore())
        self.assertEqual(self.rows(), [self.login])
        self.assertEqual(self.history(), history)
        self.assertEqual(history[-1][1], "in the wal")
        con = sqlite3.connect(self.db)
        self.assertEqual(con.execute("PRAGMA integrity_check").fetchone(), ("ok",))
        con.close()

    def test_users_without_salt_columns_is_refused(self):
        con = sqlite3.connect(self.db)
        con.executescript(
            'DROP TABLE Users; CREATE TABLE "Users" ("Id" INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, "Identifier" TEXT NOT NULL, "Username" TEXT NOT NULL, '
            '"Password" TEXT NOT NULL);'
        )
        con.close()
        err = self.restore_fails()
        self.assertIn("Users has no column(s) ['Iterations', 'Salt']", err)

    def test_command_line(self):
        self.assertEqual(
            arr_sync.main(["arr-sync", "restore-login", self.db, self.secret]), 0
        )
        self.assertEqual(self.rows(), [self.login])
        bad = self.write_secret(dict(self.login, iterations=0), "bad")
        with self.assertRaises(SystemExit) as caught:
            arr_sync.main(["arr-sync", "restore-login", self.db, bad])
        self.assertIn(
            "nothing written: login secret: 'iterations'", str(caught.exception)
        )

    def test_other_user_name_is_a_conflict(self):
        self.insert(dict(self.login, username="someone"))
        err = self.restore_fails()
        self.assertIn("(username)", err)

    def test_legacy_unsalted_login_is_a_conflict(self):
        self.insert(dict(self.login, salt=None, iterations=None))
        err = self.restore_fails()
        self.assertIn("(iterations, salt)", err)

    def test_open_database_is_refused(self):
        # the running app: a WAL connection that has read the database
        app = sqlite3.connect(self.db)
        app.execute("SELECT COUNT(*) FROM Users").fetchone()
        try:
            err = self.restore_fails()
        finally:
            app.close()
        self.assertIn("database in use", err)
        self.assertEqual(self.rows(), [])

    def test_no_database_yet_creates_nothing(self):
        os.remove(self.db)
        out = self.restore()
        self.assertIn("no database yet", out)
        self.assertFalse(os.path.exists(self.db))

    def test_no_users_table_yet_writes_nothing(self):
        con = sqlite3.connect(self.db)
        con.execute("DROP TABLE Users")
        con.commit()
        con.close()
        before = file_digest(self.db)
        out = self.restore()
        self.assertIn("no Users table yet", out)
        self.assertEqual(file_digest(self.db), before)

    def test_invalid_secret_is_refused_before_the_database(self):
        cases = {
            "plaintext password": dict(self.login, password=LOGIN_PASSWORD),
            "short salt": dict(self.login, salt=base64.b64encode(b"x" * 8).decode()),
            "uppercase name": dict(self.login, username="Admin"),
            "extra key": dict(self.login, plain=LOGIN_PASSWORD),
            "missing key": {k: v for k, v in self.login.items() if k != "salt"},
            "boolean iterations": dict(self.login, iterations=True),
            "uppercase guid": dict(
                self.login, identifier=self.login["identifier"].upper()
            ),
        }
        before = file_digest(self.db)
        for case, value in cases.items():
            with self.subTest(case):
                err = self.restore_fails(self.write_secret(value, "bad"))
                self.assertIn("login secret", err)
        err = self.restore_fails(self.write_secret("not json", "bad"))
        self.assertIn("not a JSON object", err)
        self.assertEqual(file_digest(self.db), before)
        self.assertEqual(self.rows(), [])


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
