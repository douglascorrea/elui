defmodule Elui.WebsiteObservabilityTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @index File.read!(Path.join(@root, "website/index.html"))
  @analytics File.read!(Path.join(@root, "website/analytics.js"))
  @pages_workflow File.read!(Path.join(@root, ".github/workflows/pages.yml"))

  test "publishes a complete large social card contract" do
    assert @index =~ ~s(<meta property="og:site_name" content="Elui" />)
    assert @index =~ ~s(<meta property="og:locale" content="en_US" />)
    assert @index =~ ~s(<meta property="og:image" content="https://elui.sh/og-elui.png" />)

    assert @index =~
             ~s(<meta property="og:image:secure_url" content="https://elui.sh/og-elui.png" />)

    assert @index =~ ~s(<meta property="og:image:type" content="image/png" />)
    assert @index =~ ~s(<meta property="og:image:width" content="1200" />)
    assert @index =~ ~s(<meta property="og:image:height" content="630" />)
    assert @index =~ ~r/<meta\s+property="og:image:alt"/
    assert @index =~ ~s(<meta name="twitter:card" content="summary_large_image" />)
    assert @index =~ ~s(<meta name="twitter:title")
    assert @index =~ ~r/<meta\s+name="twitter:description"/
    assert @index =~ ~s(<meta name="twitter:image" content="https://elui.sh/og-elui.png" />)
    assert @index =~ ~r/<meta\s+name="twitter:image:alt"/
    assert File.exists?(Path.join(@root, "website/og-elui.png"))
  end

  test "ships privacy-conscious PostHog tracking across the site" do
    assert @index =~ ~s(<meta name="posthog-project-token" content="__POSTHOG_PROJECT_TOKEN__" />)
    assert @index =~ ~s(<meta name="posthog-api-host" content="https://us.i.posthog.com" />)
    assert @index =~ ~s(<script src="./analytics.js" defer></script>)

    assert @analytics =~ ~s(cookieless_mode: "always")
    assert @analytics =~ ~s(person_profiles: "identified_only")
    assert @analytics =~ ~s(capture_pageview: true)
    assert @analytics =~ ~s(capture_pageleave: true)
    assert @analytics =~ ~s(capture_performance: true)
    assert @analytics =~ ~s(disable_session_recording: true)
    assert @analytics =~ "elui_home_viewed"
    assert @analytics =~ "outbound_link_clicked"
    assert @analytics =~ "content_scroll_depth_reached"
    assert @analytics =~ "engaged_reader"
    assert @analytics =~ "social_referral_landed"
    assert @analytics =~ "ai_referral_landed"
    assert @analytics =~ "example_played"
    assert @index =~ "example_filter_selected"
  end

  test "injects the capture token only while building the Pages artifact" do
    assert @pages_workflow =~ ~s(POSTHOG_PROJECT_TOKEN: \${{ secrets.POSTHOG_PROJECT_TOKEN }})
    assert @pages_workflow =~ "__POSTHOG_PROJECT_TOKEN__"
    refute @index =~ "phc_"
  end
end
