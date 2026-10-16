import { describe, expect, it } from "bun:test";
import { cleanLinks, extractUrls, replyText, stripTracking } from "../src/links.ts";

describe("extractUrls", () => {
  it("returns the text of url entities", () => {
    const text = "http://example.com http://another.com";
    const entities = [
      { type: "url", offset: 0, length: 18 },
      { type: "url", offset: 19, length: 18 },
    ];
    expect(extractUrls(text, entities)).toEqual(["http://example.com", "http://another.com"]);
  });

  it("skips other entities", () => {
    const text = "@someone see http://example.com";
    const entities = [
      { type: "mention", offset: 0, length: 8 },
      { type: "url", offset: 13, length: 18 },
    ];
    expect(extractUrls(text, entities)).toEqual(["http://example.com"]);
  });

  it("slices by UTF-16 offsets", () => {
    const text = "👋 http://example.com";
    expect(extractUrls(text, [{ type: "url", offset: 3, length: 18 }])).toEqual([
      "http://example.com",
    ]);
  });
});

describe("stripTracking", () => {
  it("removes tracking parameters", () => {
    expect(stripTracking("http://example.com/?utm_source=google&utm_medium=cpc")).toBe(
      "http://example.com/",
    );
  });

  it("keeps other parameters", () => {
    expect(stripTracking("http://example.com/?utm_source=google&foo=1&utm_medium=cpc")).toBe(
      "http://example.com/?foo=1",
    );
  });

  it("removes a site's own tracking parameters", () => {
    expect(stripTracking("https://www.youtube.com/watch?v=abc&si=xyz&pp=123")).toBe(
      "https://www.youtube.com/watch?v=abc",
    );
    expect(stripTracking("https://x.com/user/status/1?s=20&t=abc")).toBe(
      "https://x.com/user/status/1",
    );
  });

  it("keeps the encoding of the remaining parameters", () => {
    expect(stripTracking("https://example.com/search?q=a,b%20c&utm_source=x")).toBe(
      "https://example.com/search?q=a,b%20c",
    );
  });

  it("keeps the fragment", () => {
    expect(stripTracking("https://youtu.be/abc?si=xyz&t=42#comments")).toBe(
      "https://youtu.be/abc?t=42#comments",
    );
  });

  it("unwraps redirects and cleans their targets", () => {
    expect(
      stripTracking("https://www.google.com/url?q=https://example.com/page%3Futm_source%3Dx&sa=D"),
    ).toBe("https://example.com/page");
  });

  it("cleans links without a scheme", () => {
    expect(stripTracking("example.com/page?fbclid=abc")).toBe("https://example.com/page");
  });

  it("returns undefined without tracking parameters", () => {
    expect(stripTracking("http://example.com/?foo=1")).toBeUndefined();
    expect(stripTracking("http://example.com/")).toBeUndefined();
  });

  it("returns undefined for an unparseable link", () => {
    expect(stripTracking("http://exa mple.com/?utm_source=x")).toBeUndefined();
  });
});

describe("cleanLinks", () => {
  it("returns only the links that had tracking parameters", () => {
    const text = "https://a.com/?gclid=1 https://b.com/?x=1";
    const entities = [
      { type: "url", offset: 0, length: 22 },
      { type: "url", offset: 23, length: 18 },
    ];
    expect(cleanLinks(text, entities)).toEqual(["https://a.com/"]);
  });
});

describe("replyText", () => {
  it("lists one link", () => {
    expect(replyText(["http://example.com"])).toBe("Ось лінк без трекінгу: http://example.com");
  });

  it("lists several links", () => {
    expect(replyText(["http://example.com", "http://another.com"])).toBe(
      "Ось лінки без трекінгу: http://example.com, http://another.com",
    );
  });
});
