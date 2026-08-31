(() => {
  "use strict";

  const compactNavigationQuery = "(max-width: 1120px)";

  const isRelatedDisclosure = (first, second) =>
    first.contains(second) || second.contains(first);

  const closeDisclosures = (disclosures, except = null) => {
    disclosures.forEach((disclosure) => {
      if (disclosure !== except && disclosure.open) {
        disclosure.open = false;
      }
    });
  };

  const summaryFor = (disclosure) =>
    disclosure?.querySelector(":scope > summary") || disclosure?.querySelector("summary");

  const initializeNavigation = (navigation) => {
    const disclosures = Array.from(navigation.querySelectorAll("details"));
    if (disclosures.length === 0) {
      return;
    }

    const inlineSurface = navigation.querySelector(".site-nav__inline");
    const compactSurface = navigation.querySelector("details.navigation-menu");
    const mediaQuery = window.matchMedia(compactNavigationQuery);

    const closeAll = () => closeDisclosures(disclosures);

    disclosures.forEach((disclosure) => {
      disclosure.addEventListener("toggle", () => {
        if (!disclosure.open) {
          return;
        }

        disclosures.forEach((otherDisclosure) => {
          if (
            otherDisclosure.open &&
            otherDisclosure !== disclosure &&
            !isRelatedDisclosure(disclosure, otherDisclosure)
          ) {
            otherDisclosure.open = false;
          }
        });
      });
    });

    navigation.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") {
        return;
      }

      const activeElement = document.activeElement;
      const openContainingFocus = disclosures
        .filter((disclosure) => disclosure.open && disclosure.contains(activeElement))
        .sort((first, second) => {
          if (first.contains(second)) return 1;
          if (second.contains(first)) return -1;
          return 0;
        });
      const disclosure = openContainingFocus[0];

      if (!disclosure) {
        return;
      }

      event.preventDefault();
      disclosure.open = false;
      summaryFor(disclosure)?.focus();
    });

    navigation.addEventListener("click", (event) => {
      if (event.target.closest("a[href]")) {
        closeAll();
      }
    });

    document.addEventListener("pointerdown", (event) => {
      if (!navigation.contains(event.target)) {
        closeAll();
      }
    });

    const focusVisibleMenu = () => {
      const visibleSummary = mediaQuery.matches
        ? summaryFor(compactSurface)
        : inlineSurface?.querySelector("details.language-menu > summary");
      const siteBrand = navigation.closest(".site-header")?.querySelector(".site-brand");
      (visibleSummary || siteBrand)?.focus();
    };

    mediaQuery.addEventListener("change", (event) => {
      const hiddenSurface = event.matches ? inlineSurface : compactSurface;
      const focusWasHidden = hiddenSurface?.contains(document.activeElement);

      closeAll();
      if (focusWasHidden) {
        focusVisibleMenu();
      }
    });
  };

  const initialize = () => {
    document.querySelectorAll(".site-header .site-nav").forEach(initializeNavigation);
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, { once: true });
  } else {
    initialize();
  }
})();
