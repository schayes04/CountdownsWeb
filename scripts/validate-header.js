"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

class FakeEvent {
  constructor(type, options = {}) {
    this.type = type;
    this.key = options.key;
    this.matches = options.matches;
    this.target = options.target || null;
    this.defaultPrevented = false;
  }

  preventDefault() {
    this.defaultPrevented = true;
  }
}

class FakeEventTarget {
  constructor() {
    this.listeners = new Map();
  }

  addEventListener(type, listener, options = {}) {
    const listeners = this.listeners.get(type) || [];
    listeners.push({ listener, once: Boolean(options.once) });
    this.listeners.set(type, listeners);
  }

  dispatchEvent(event) {
    if (!event.target) {
      event.target = this;
    }

    const listeners = [...(this.listeners.get(event.type) || [])];
    for (const entry of listeners) {
      entry.listener.call(this, event);
      if (entry.once) {
        const current = this.listeners.get(event.type) || [];
        this.listeners.set(event.type, current.filter((item) => item !== entry));
      }
    }

    return !event.defaultPrevented;
  }
}

class FakeElement extends FakeEventTarget {
  constructor(document, tagName, classes = [], attributes = {}) {
    super();
    this.document = document;
    this.tagName = tagName.toLowerCase();
    this.classList = new Set(classes);
    this.attributes = { ...attributes };
    this.children = [];
    this.parentElement = null;
    this.open = false;
    this.focusCount = 0;
  }

  append(...children) {
    for (const child of children) {
      child.parentElement = this;
      this.children.push(child);
    }
    return this;
  }

  contains(candidate) {
    if (candidate === this) {
      return true;
    }
    return this.children.some((child) => child.contains(candidate));
  }

  matches(selector) {
    if (selector === "details") return this.tagName === "details";
    if (selector === "summary") return this.tagName === "summary";
    if (selector === "a[href]") return this.tagName === "a" && "href" in this.attributes;
    if (selector === ".site-nav__inline") return this.classList.has("site-nav__inline");
    if (selector === ".site-header") return this.classList.has("site-header");
    if (selector === ".site-nav") return this.classList.has("site-nav");
    if (selector === "details.navigation-menu") {
      return this.tagName === "details" && this.classList.has("navigation-menu");
    }
    if (selector === "details.language-menu") {
      return this.tagName === "details" && this.classList.has("language-menu");
    }
    return false;
  }

  descendants() {
    return this.children.flatMap((child) => [child, ...child.descendants()]);
  }

  querySelectorAll(selector) {
    if (selector.includes(" > ")) {
      const [parentSelector, childSelector] = selector.split(" > ");
      return this.querySelectorAll(parentSelector).flatMap((parent) =>
        parent.children.filter((child) => child.matches(childSelector)),
      );
    }

    if (selector.includes(" ")) {
      const [ancestorSelector, descendantSelector] = selector.split(" ");
      return this.querySelectorAll(descendantSelector).filter((element) =>
        element.parentElement && element.parentElement.closest(ancestorSelector),
      );
    }

    return this.descendants().filter((element) => element.matches(selector));
  }

  querySelector(selector) {
    if (selector === ":scope > summary") {
      return this.children.find((child) => child.matches("summary")) || null;
    }
    return this.querySelectorAll(selector)[0] || null;
  }

  closest(selector) {
    let current = this;
    while (current) {
      if (current.matches(selector)) {
        return current;
      }
      current = current.parentElement;
    }
    return null;
  }

  focus() {
    this.document.activeElement = this;
    this.focusCount += 1;
  }
}

class FakeDocument extends FakeEventTarget {
  constructor(readyState = "complete") {
    super();
    this.readyState = readyState;
    this.activeElement = null;
    this.root = new FakeElement(this, "document");
  }

  querySelectorAll(selector) {
    return this.root.querySelectorAll(selector);
  }
}

class FakeMediaQuery extends FakeEventTarget {
  constructor(matches = false) {
    super();
    this.matches = matches;
  }

  setMatches(matches) {
    this.matches = matches;
    this.dispatchEvent(new FakeEvent("change", { matches }));
  }
}

const element = (document, tagName, classes, attributes) =>
  new FakeElement(document, tagName, classes, attributes);

const createPage = ({ readyState = "complete", withNavigation = true } = {}) => {
  const document = new FakeDocument(readyState);
  const mediaQuery = new FakeMediaQuery(false);
  const page = { document, mediaQuery };

  page.header = element(document, "header", ["site-header"]);
  page.brand = element(document, "a", ["site-brand"], { href: "/" });
  page.header.append(page.brand);
  document.root.append(page.header);

  if (!withNavigation) {
    return page;
  }

  page.navigation = element(document, "nav", ["site-nav"]);
  page.inlineSurface = element(document, "div", ["site-nav__inline"]);
  page.inlineLanguage = element(document, "details", ["language-menu"]);
  page.inlineLanguageSummary = element(document, "summary");
  page.inlineLanguageLink = element(document, "a", [], { href: "/fi/" });
  page.inlineLanguage.append(page.inlineLanguageSummary, page.inlineLanguageLink);
  page.inlineSurface.append(page.inlineLanguage);

  page.compactMenu = element(document, "details", ["navigation-menu"]);
  page.compactSummary = element(document, "summary");
  page.compactPanel = element(document, "div", ["navigation-menu__panel"]);
  page.compactLink = element(document, "a", [], { href: "/countdown-ideas/" });
  page.compactLanguage = element(document, "details", ["language-menu"]);
  page.compactLanguageSummary = element(document, "summary");
  page.compactLanguageLink = element(document, "a", [], { href: "/sv/" });
  page.compactLanguage.append(page.compactLanguageSummary, page.compactLanguageLink);
  page.compactPanel.append(page.compactLink, page.compactLanguage);
  page.compactMenu.append(page.compactSummary, page.compactPanel);
  page.navigation.append(page.inlineSurface, page.compactMenu);
  page.header.append(page.navigation);
  return page;
};

const loadHeader = (page) => {
  const source = fs.readFileSync(path.join(__dirname, "..", "assets", "header.js"), "utf8");
  const window = { matchMedia: () => page.mediaQuery };
  vm.runInNewContext(source, { document: page.document, window });
};

const toggle = (details, open) => {
  details.open = open;
  details.dispatchEvent(new FakeEvent("toggle", { target: details }));
};

const allMenusClosed = (page) =>
  [page.inlineLanguage, page.compactMenu, page.compactLanguage].every((details) => !details.open);

const test = (name, callback) => {
  callback();
  console.log(`✓ ${name}`);
};

test("initializes after DOMContentLoaded", () => {
  const page = createPage({ readyState: "loading" });
  loadHeader(page);
  toggle(page.inlineLanguage, true);
  assert.equal(page.inlineLanguage.open, true, "the listener should not be attached before DOMContentLoaded");

  page.document.dispatchEvent(new FakeEvent("DOMContentLoaded"));
  toggle(page.compactMenu, true);
  assert.equal(page.inlineLanguage.open, false);
});

test("initializes immediately when the document is already ready", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.inlineLanguage, true);
  toggle(page.compactMenu, true);
  assert.equal(page.inlineLanguage.open, false);
});

test("keeps a compact menu open when its nested language disclosure opens", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.compactMenu, true);
  toggle(page.compactLanguage, true);
  assert.equal(page.compactMenu.open, true);
  assert.equal(page.compactLanguage.open, true);
});

test("opening an unrelated language disclosure closes the other disclosure", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.compactMenu, true);
  toggle(page.inlineLanguage, true);
  assert.equal(page.inlineLanguage.open, true);
  assert.equal(page.compactMenu.open, false);
  assert.equal(page.compactLanguage.open, false);
});

test("Escape closes the inner disclosure first, then its outer menu, and focuses each summary", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.compactMenu, true);
  toggle(page.compactLanguage, true);
  page.compactLanguageLink.focus();

  const firstEscape = new FakeEvent("keydown", { key: "Escape", target: page.navigation });
  page.navigation.dispatchEvent(firstEscape);
  assert.equal(firstEscape.defaultPrevented, true);
  assert.equal(page.compactLanguage.open, false);
  assert.equal(page.compactMenu.open, true);
  assert.equal(page.document.activeElement, page.compactLanguageSummary);

  const secondEscape = new FakeEvent("keydown", { key: "Escape", target: page.navigation });
  page.navigation.dispatchEvent(secondEscape);
  assert.equal(secondEscape.defaultPrevented, true);
  assert.equal(page.compactMenu.open, false);
  assert.equal(page.document.activeElement, page.compactSummary);
});

test("an outside pointerdown closes every disclosure", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.compactMenu, true);
  toggle(page.compactLanguage, true);
  page.document.dispatchEvent(new FakeEvent("pointerdown", { target: page.brand }));
  assert.equal(allMenusClosed(page), true);
});

test("an internal link click closes every disclosure", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.compactMenu, true);
  toggle(page.compactLanguage, true);
  page.navigation.dispatchEvent(new FakeEvent("click", { target: page.compactLanguageLink }));
  assert.equal(allMenusClosed(page), true);
});

test("an inside pointerdown leaves menus open", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.compactMenu, true);
  toggle(page.compactLanguage, true);
  page.document.dispatchEvent(new FakeEvent("pointerdown", { target: page.compactLanguageLink }));
  assert.equal(page.compactMenu.open, true);
  assert.equal(page.compactLanguage.open, true);
});

test("narrowing closes menus and moves focus only from the hidden inline surface", () => {
  const page = createPage();
  loadHeader(page);
  toggle(page.inlineLanguage, true);
  page.inlineLanguageLink.focus();
  page.mediaQuery.setMatches(true);
  assert.equal(allMenusClosed(page), true);
  assert.equal(page.document.activeElement, page.compactSummary);

  toggle(page.inlineLanguage, true);
  page.brand.focus();
  page.mediaQuery.setMatches(false);
  page.mediaQuery.setMatches(true);
  assert.equal(allMenusClosed(page), true);
  assert.equal(page.document.activeElement, page.brand);
});

test("widening closes menus and moves focus from the hidden compact surface to inline language", () => {
  const page = createPage();
  loadHeader(page);
  page.mediaQuery.setMatches(true);
  toggle(page.compactMenu, true);
  page.compactLanguageLink.focus();
  page.mediaQuery.setMatches(false);
  assert.equal(allMenusClosed(page), true);
  assert.equal(page.document.activeElement, page.inlineLanguageSummary);
});

test("a header without navigation initializes harmlessly", () => {
  const page = createPage({ withNavigation: false });
  assert.doesNotThrow(() => loadHeader(page));
});
