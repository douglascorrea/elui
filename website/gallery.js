const exampleCatalog = [
  {
    name: "beam_lab",
    title: "BEAM Lab",
    category: "apps",
    description: "Supervisors, GenServers, distributed nodes, RPC, and a live GitHub event stream."
  },
  {
    name: "async_github",
    title: "Async GitHub",
    category: "apps",
    description: "Recent elixir-lang/elixir commits fetched asynchronously into a selectable table."
  },
  {
    name: "mouse_drawing",
    title: "Mouse Drawing",
    category: "apps",
    description: "Continuous full-block lines drawn from real SGR click-and-drag events."
  },
  {
    name: "flex",
    title: "Flex Layout",
    category: "apps",
    description: "Scrollable flex modes, fills, alignments, spacing, and colored layout blocks."
  },
  {
    name: "calendar_explorer",
    title: "Calendar Explorer",
    category: "apps",
    description: "Month and day navigation with calendar styles that change at runtime."
  },
  {
    name: "volatility_surface",
    title: "Volatility Surface",
    category: "apps",
    description: "An interactive 3D wireframe surface with rotation and zoom controls."
  },
  {
    name: "demo",
    title: "Widget Tour",
    category: "apps",
    description: "Core widgets, styled text, gauges, lists, and calendar views in one app."
  },
  {
    name: "demo2",
    title: "Application Suite",
    category: "apps",
    description: "A tabbed inbox, recipe, traceroute, and weather application showcase."
  },
  {
    name: "input_form",
    title: "Input Form",
    category: "apps",
    description: "Multi-field focus, digit validation, cursor handling, and submitted state."
  },
  {
    name: "todo_list",
    title: "Todo List",
    category: "apps",
    description: "Add, select, complete, and delete tasks through a stateful terminal workflow."
  },
  {
    name: "user_input",
    title: "User Input",
    category: "apps",
    description: "Cursor-aware text editing with submitted messages retained in application state."
  },
  {
    name: "weather",
    title: "Weather Dashboard",
    category: "apps",
    description: "A compact forecast composed from bar charts, gauges, and summary panels."
  },
  {
    name: "advanced_widget_impl",
    title: "Advanced Widget Protocol",
    category: "widgets",
    description: "Custom structs implementing Elui.Widget alongside animated gauges and charts."
  },
  {
    name: "canvas",
    title: "Canvas",
    category: "widgets",
    description: "Animated braille-resolution primitives rendered inside the terminal grid."
  },
  {
    name: "chart",
    title: "Chart",
    category: "widgets",
    description: "Animated line and scatter datasets with labels, axes, and bounds."
  },
  {
    name: "color_explorer",
    title: "Color Explorer",
    category: "widgets",
    description: "Named terminal colors with keyboard selection and live swatches."
  },
  {
    name: "colors_rgb",
    title: "RGB Colors",
    category: "widgets",
    description: "A moving 24-bit truecolor field rendered directly into terminal cells."
  },
  {
    name: "custom_widget",
    title: "Custom Widget",
    category: "widgets",
    description: "A reusable button widget responding to keyboard and mouse interaction."
  },
  {
    name: "gauge",
    title: "Gauge",
    category: "widgets",
    description: "Start, pause, and inspect progress across gauge, line, and history views."
  },
  {
    name: "gauges",
    title: "Gauge Collection",
    category: "widgets",
    description: "Gauge, LineGauge, Sparkline, and BarChart widgets animating together."
  },
  {
    name: "hyperlink",
    title: "Hyperlink",
    category: "widgets",
    description: "OSC 8 terminal hyperlinks paired with a readable fallback URL."
  },
  {
    name: "list",
    title: "Stateful List",
    category: "widgets",
    description: "Selection, first-to-last navigation, highlighting, and scrollbar state."
  },
  {
    name: "modifiers",
    title: "Style Modifiers",
    category: "widgets",
    description: "An interactive survey of bold, dim, italic, underline, and related styles."
  },
  {
    name: "popup",
    title: "Popup",
    category: "widgets",
    description: "A centered modal overlay rendered after clearing the covered buffer region."
  },
  {
    name: "release_header",
    title: "Release Header",
    category: "widgets",
    description: "A release dashboard composition with status, metadata, and progress regions."
  },
  {
    name: "scrollbar",
    title: "Scrollbar",
    category: "widgets",
    description: "Vertical and horizontal scrolling across a large paragraph viewport."
  },
  {
    name: "table",
    title: "Stateful Table",
    category: "widgets",
    description: "Row selection and highlighting across aligned terminal table columns."
  },
  {
    name: "widget_ref_container",
    title: "Widget References",
    category: "widgets",
    description: "Heterogeneous widget references selected and rendered from one container."
  },
  {
    name: "constraint_explorer",
    title: "Constraint Explorer",
    category: "layout",
    description: "Edit constraints and direction while every resulting rectangle recomputes live."
  },
  {
    name: "constraints",
    title: "Constraints",
    category: "layout",
    description: "Length, Percentage, Ratio, Fill, Min, and Max constraints compared side by side."
  },
  {
    name: "layout",
    title: "Nested Layout",
    category: "layout",
    description: "Nested horizontal and vertical splits built from composable constraints."
  },
  {
    name: "inline",
    title: "Inline Viewport",
    category: "layout",
    description: "Rendering without the alternate screen so normal terminal scrollback remains."
  },
  {
    name: "hello_world",
    title: "Hello World",
    category: "runtime",
    description: "The smallest bordered Elui application and quit loop."
  },
  {
    name: "minimal",
    title: "Minimal App",
    category: "runtime",
    description: "A compact Elui.App implementation driven by terminal events and ticks."
  },
  {
    name: "panic",
    title: "Panic Recovery",
    category: "runtime",
    description: "Terminal restoration guarantees around intentional application exceptions."
  },
  {
    name: "tracing",
    title: "Tracing",
    category: "runtime",
    description: "An animated event stream that can pause and resume without losing app state."
  }
];

const categoryLabels = {
  apps: "Application",
  widgets: "Widget",
  layout: "Layout",
  runtime: "Runtime"
};

const exampleGrid = document.querySelector("#example-grid");

if (exampleGrid) {
  exampleGrid.innerHTML = exampleCatalog
    .map((example, index) => {
      const video = `./videos/${example.name}.mp4`;
      const poster = `./videos/posters/${example.name}.jpg`;
      const source = `https://github.com/douglascorrea/elui/blob/master/examples/${example.name}.exs`;
      const number = String(index + 1).padStart(2, "0");

      return `
        <article class="example-card" data-category="${example.category}">
          <div class="example-media">
            <video
              controls
              muted
              playsinline
              preload="metadata"
              poster="${poster}"
              data-example-name="${example.name}"
              data-example-category="${example.category}"
              aria-label="${example.title} example recording"
            >
              <source src="${video}" type="video/mp4" />
              <a href="${video}">Open the ${example.title} recording</a>
            </video>
            <button class="example-play" type="button" data-ph-event="example_play_requested" data-ph-example="${example.name}" data-ph-category="${example.category}" aria-label="Play ${example.title} recording">
              <span aria-hidden="true">&#9654;</span>
            </button>
            <span class="example-category">${categoryLabels[example.category]}</span>
          </div>
          <div class="example-card-body">
            <div class="example-card-heading">
              <h3>${example.title}</h3>
              <span aria-hidden="true">${number}</span>
            </div>
            <code class="example-file">${example.name}.exs</code>
            <p>${example.description}</p>
            <a class="source-link" href="${source}" data-ph-event="resource_clicked" data-ph-resource="example_source" data-ph-example="${example.name}">View source</a>
          </div>
        </article>
      `;
    })
    .join("");

  const cards = [...exampleGrid.querySelectorAll(".example-card")];
  const videos = [...exampleGrid.querySelectorAll("video")];
  const filterButtons = [...document.querySelectorAll(".example-filter")];
  const exampleCount = document.querySelector("#example-count");

  function applyFilter(filter) {
    let visible = 0;

    cards.forEach((card) => {
      const matches = filter === "all" || card.dataset.category === filter;
      card.hidden = !matches;

      if (matches) {
        visible += 1;
      } else {
        card.querySelector("video").pause();
      }
    });

    filterButtons.forEach((button) => {
      const active = button.dataset.filter === filter;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });

    exampleCount.textContent = `${visible} ${visible === 1 ? "example" : "examples"}`;
  }

  filterButtons.forEach((button) => {
    button.addEventListener("click", () => applyFilter(button.dataset.filter));
  });

  videos.forEach((video) => {
    const playButton = video.parentElement.querySelector(".example-play");

    playButton.addEventListener("click", async () => {
      delete playButton.dataset.playbackError;

      try {
        await video.play();
      } catch (error) {
        playButton.dataset.playbackError = error.name;
        playButton.hidden = false;
      }
    });

    video.addEventListener("play", () => {
      playButton.hidden = true;

      videos.forEach((otherVideo) => {
        if (otherVideo !== video) otherVideo.pause();
      });
    });

    video.addEventListener("pause", () => {
      playButton.hidden = false;
    });
  });
}
