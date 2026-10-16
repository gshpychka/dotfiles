import type { MessageEntity } from "./telegram.ts";

/** Query parameters that only carry tracking data. */
export const trackingParameters: ReadonlySet<string> = new Set([
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_name",
  "utm_term",
  "utm_content",
  "gclid",
  "fbclid",
  "igshid",
  "mc_eid",
  "mc_cid",
  "_hsenc",
  "_hsmi",
  "hsCtaTracking",
  "si",
]);

const schemePattern = /^[a-z][a-z\d+.-]*:\/\//i;

/** The links Telegram marked in a message's text. */
export const extractUrls = (text: string, entities: readonly MessageEntity[]): string[] =>
  entities
    .filter((entity) => entity.type === "url")
    .map((entity) => text.slice(entity.offset, entity.offset + entity.length));

/** `link` without its tracking parameters, or undefined when it has none. */
export const stripTracking = (link: string): string | undefined => {
  // Telegram also marks links without a scheme (example.com/page); they parse
  // against https and keep their schemeless form
  const schemeless = !schemePattern.test(link);
  const url = URL.parse(schemeless ? `https://${link}` : link);
  if (url === null) return undefined;

  // raw pairs keep the remaining parameters byte for byte; URLSearchParams
  // would re-encode them
  const pairs = url.search.slice(1).split("&");
  const kept = pairs.filter((pair) => {
    const [name] = new URLSearchParams(pair).keys();
    return name === undefined || !trackingParameters.has(name);
  });
  if (kept.length === pairs.length) return undefined;

  url.search = kept.join("&");
  return schemeless ? url.href.slice("https://".length) : url.href;
};

/** The message's links that carry tracking parameters, stripped of them. */
export const cleanLinks = (text: string, entities: readonly MessageEntity[]): string[] =>
  extractUrls(text, entities).flatMap((link) => stripTracking(link) ?? []);

/** The reply that lists the cleaned links. */
export const replyText = (links: readonly string[]): string =>
  `${links.length === 1 ? "Ось лінк" : "Ось лінки"} без трекінгу: ${links.join(", ")}`;
