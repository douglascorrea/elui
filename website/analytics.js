(function () {
  "use strict";

  var tokenMeta = document.querySelector('meta[name="posthog-project-token"]');
  var hostMeta = document.querySelector('meta[name="posthog-api-host"]');
  var uiHostMeta = document.querySelector('meta[name="posthog-ui-host"]');

  if (!tokenMeta || !hostMeta) return;

  var projectToken = tokenMeta.content.trim();
  if (!projectToken || projectToken === "__POSTHOG_PROJECT_TOKEN__") return;

  var apiHost = hostMeta.content;
  var client = null;
  var pending = [];
  var pageContext = {
    event: "elui_home_viewed",
    properties: {
      page_type: "marketing",
      product: "elui"
    }
  };

  function mergedProperties(properties) {
    return Object.assign({}, pageContext.properties, properties || {});
  }

  function capture(eventName, properties) {
    if (!eventName) return;

    var enriched = mergedProperties(properties);
    if (client) client.capture(eventName, enriched);
    else pending.push([eventName, enriched]);
  }

  function snakeCase(value) {
    return value.replace(/[A-Z]/g, function (letter) {
      return "_" + letter.toLowerCase();
    });
  }

  function trackedProperties(target) {
    var properties = {};

    Object.keys(target.dataset).forEach(function (key) {
      if (key.indexOf("ph") === 0 && key !== "phEvent") {
        var property = key.slice(2).replace(/^./, function (letter) {
          return letter.toLowerCase();
        });

        properties[snakeCase(property)] = target.dataset[key];
      }
    });

    return properties;
  }

  function boundedText(value) {
    return (value || "").trim().replace(/\s+/g, " ").slice(0, 160);
  }

  document.addEventListener("click", function (event) {
    var target = event.target.closest("[data-ph-event]");

    if (target) {
      capture(target.dataset.phEvent, trackedProperties(target));
    }

    var link = event.target.closest("a[href]");
    if (!link) return;

    try {
      var destination = new URL(link.href, window.location.href);
      if (destination.hostname && destination.hostname !== window.location.hostname) {
        capture("outbound_link_clicked", {
          destination_host: destination.hostname,
          destination_url: destination.origin + destination.pathname,
          link_text: boundedText(link.textContent),
          surface: link.dataset.phSurface || "page"
        });
      }
    } catch (_error) {
      return;
    }
  });

  document.addEventListener("play", function (event) {
    var video = event.target;
    if (!video.matches("video[data-example-name]")) return;

    capture("example_played", {
      example: video.dataset.exampleName,
      category: video.dataset.exampleCategory
    });
  }, true);

  function referralContext() {
    var params = new URLSearchParams(window.location.search);
    var utmSource = params.get("utm_source");
    var referrerHost = "";

    try {
      referrerHost = document.referrer ? new URL(document.referrer).hostname : "";
    } catch (_error) {
      referrerHost = "";
    }

    return {
      params: params,
      utmSource: utmSource,
      normalizedUtmSource: (utmSource || "").toLowerCase(),
      referrerHost: referrerHost,
      normalizedHost: referrerHost.toLowerCase().replace(/^www\./, "")
    };
  }

  function matchesReferralDomain(host, domains) {
    return domains.some(function (domain) {
      return host === domain || host.slice(-(domain.length + 1)) === "." + domain;
    });
  }

  function captureSocialReferral() {
    var context = referralContext();
    var socialSources = ["facebook", "instagram", "twitter", "x", "tiktok", "reddit", "youtube"];
    var socialDomains = ["facebook.com", "instagram.com", "twitter.com", "x.com", "tiktok.com", "reddit.com", "youtube.com", "youtu.be"];
    var socialSource = socialSources.indexOf(context.normalizedUtmSource) !== -1;
    var socialHost = matchesReferralDomain(context.normalizedHost, socialDomains);

    if (!socialSource && !socialHost) return;

    capture("social_referral_landed", {
      utm_source: context.utmSource || "referral",
      utm_medium: context.params.get("utm_medium") || "",
      utm_campaign: context.params.get("utm_campaign") || "",
      referrer_host: context.referrerHost
    });
  }

  function captureAIReferral() {
    var context = referralContext();
    var sources = [
      { name: "chatgpt", utm: ["chatgpt", "openai"], domains: ["chatgpt.com"] },
      { name: "perplexity", utm: ["perplexity"], domains: ["perplexity.ai", "perplexity.com"] },
      { name: "copilot", utm: ["copilot", "microsoft-copilot"], domains: ["copilot.microsoft.com"] },
      { name: "claude", utm: ["claude", "anthropic"], domains: ["claude.ai"] },
      { name: "gemini", utm: ["gemini", "google-gemini"], domains: ["gemini.google.com"] }
    ];

    var match = sources.find(function (source) {
      return source.utm.indexOf(context.normalizedUtmSource) !== -1 ||
        matchesReferralDomain(context.normalizedHost, source.domains);
    });

    if (!match) return;

    capture("ai_referral_landed", {
      ai_source: match.name,
      utm_source: context.normalizedUtmSource || "referral",
      utm_medium: context.params.get("utm_medium") || "",
      utm_campaign: context.params.get("utm_campaign") || "",
      referrer_host: context.referrerHost
    });
  }

  function installScrollDepthTracking() {
    var thresholds = [25, 50, 75, 100];
    var reached = {};
    var scheduled = false;

    function measure() {
      scheduled = false;
      var scrollable = document.documentElement.scrollHeight - window.innerHeight;
      var depth = scrollable <= 0 ? 100 : Math.min(100, Math.round((window.scrollY / scrollable) * 100));

      thresholds.forEach(function (threshold) {
        if (depth >= threshold && !reached[threshold]) {
          reached[threshold] = true;
          capture("content_scroll_depth_reached", { depth_percent: threshold });
        }
      });
    }

    window.addEventListener("scroll", function () {
      if (scheduled) return;
      scheduled = true;
      window.requestAnimationFrame(measure);
    }, { passive: true });

    measure();
  }

  function installEngagedReaderTracking() {
    var visibleSeconds = 0;
    var reported = false;

    window.setInterval(function () {
      if (reported || document.visibilityState !== "visible") return;

      visibleSeconds += 1;
      if (visibleSeconds >= 30) {
        reported = true;
        capture("engaged_reader", { engagement_seconds: visibleSeconds });
      }
    }, 1000);
  }

  captureSocialReferral();
  captureAIReferral();
  installScrollDepthTracking();
  installEngagedReaderTracking();

  var script = document.createElement("script");
  script.async = true;
  script.crossOrigin = "anonymous";
  script.src = apiHost.replace(".i.posthog.com", "-assets.i.posthog.com") + "/static/array.js";
  script.onload = function () {
    if (!window.posthog || typeof window.posthog.init !== "function") return;

    client = window.posthog;
    client.init(projectToken, {
      api_host: apiHost,
      ui_host: uiHostMeta ? uiHostMeta.content : "https://us.posthog.com",
      defaults: "2026-05-30",
      cookieless_mode: "always",
      person_profiles: "identified_only",
      autocapture: {
        dom_event_allowlist: ["click"],
        element_allowlist: ["a", "button"]
      },
      capture_pageview: true,
      capture_pageleave: true,
      capture_performance: true,
      disable_session_recording: true
    });

    capture(pageContext.event, pageContext.properties);

    pending.splice(0).forEach(function (entry) {
      capture(entry[0], entry[1]);
    });
  };

  document.head.appendChild(script);
})();
