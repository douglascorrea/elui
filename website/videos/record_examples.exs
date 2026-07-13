#!/usr/bin/env elixir

# Record every example, one example, or inspect the catalog:
#
#   website/videos/record_examples.exs --all
#   website/videos/record_examples.exs mouse_drawing
#   website/videos/record_examples.exs --list

defmodule EluiExampleRecorder do
  @moduledoc false

  @root Path.expand("../..", __DIR__)
  @video_dir Path.join(@root, "website/videos")
  @poster_dir Path.join(@video_dir, "posters")

  @theme ~s(Set Theme { "name": "Elui", "black": "#10110d", "red": "#ff7248", "green": "#9fdd3a", "yellow": "#f2b84b", "blue": "#4b8dcc", "magenta": "#d783ff", "cyan": "#3bd6cc", "white": "#f1ecd9", "brightBlack": "#66695f", "brightRed": "#ff8c6a", "brightGreen": "#c7ff45", "brightYellow": "#ffd36a", "brightBlue": "#72a7ff", "brightMagenta": "#e29aff", "brightCyan": "#3bd6cc", "brightWhite": "#ffffff", "background": "#10110d", "foreground": "#c9c0a5", "selection": "#2a3620", "cursor": "#c7ff45" })

  def main(args) do
    ensure_tools!()
    File.mkdir_p!(@poster_dir)

    examples = examples()

    if args == ["--list"] do
      Enum.each(examples, &IO.puts(&1.name))
    else
      selected = select_examples!(examples, args)
      total = length(selected)

      selected
      |> Enum.with_index(1)
      |> Enum.each(fn {example, index} -> record(example, index, total) end)

      IO.puts("Recorded #{total} Elui example#{if total == 1, do: "", else: "s"}.")
    end
  end

  defp examples do
    [
      example("advanced_widget_impl", [sleep: 6_000], poster: 4.0),
      example(
        "async_github",
        [sleep: 3_000, type: "jjj", sleep: 1_400, type: "k", sleep: 1_600],
        startup: 1_200,
        poster: 5.0
      ),
      example(
        "beam_lab",
        [sleep: 1_500, type: "n", sleep: 2_000, type: "c", sleep: 3_000, type: "f", sleep: 3_000],
        env: %{
          "ELUI_BEAM_LAB_COOKIE" => "elui_demo",
          "ELUI_BEAM_LAB_HOST" => "127.0.0.1"
        },
        peer: true,
        startup: 2_000,
        poster: 8.5
      ),
      example(
        "calendar_explorer",
        [
          sleep: 700,
          type: "s",
          sleep: 900,
          type: "llll",
          sleep: 900,
          type: "n",
          sleep: 1_100,
          type: "s",
          sleep: 1_200
        ],
        poster: 4.5
      ),
      example("canvas", [sleep: 6_000], poster: 4.0),
      example("chart", [sleep: 6_000], poster: 4.0),
      example(
        "color_explorer",
        [
          sleep: 600,
          type: "jjj",
          sleep: 1_000,
          type: "jj",
          sleep: 1_000,
          type: "kk",
          sleep: 1_200
        ],
        poster: 3.5
      ),
      example("colors_rgb", [sleep: 6_000], poster: 4.0),
      example(
        "constraint_explorer",
        [
          sleep: 600,
          type: "lll",
          sleep: 800,
          type: "j",
          type: "t",
          sleep: 900,
          type: "d",
          sleep: 1_500
        ],
        poster: 3.6
      ),
      example(
        "constraints",
        [sleep: 600, type: "l", sleep: 1_000, type: "l", sleep: 1_000, type: "h", sleep: 1_200],
        poster: 2.8
      ),
      example(
        "custom_widget",
        [
          sleep: 500,
          type: "l",
          sleep: 600,
          space: 1,
          sleep: 1_000,
          type: "l",
          sleep: 600,
          space: 1,
          sleep: 1_400
        ],
        poster: 3.8
      ),
      example(
        "demo",
        [
          sleep: 600,
          type: "jjj",
          sleep: 900,
          type: "l",
          sleep: 1_100,
          type: "l",
          sleep: 1_100,
          type: "h",
          sleep: 1_300
        ],
        poster: 4.3
      ),
      example(
        "demo2",
        [
          sleep: 500,
          type: "l",
          sleep: 1_000,
          type: "jjj",
          sleep: 800,
          type: "l",
          sleep: 1_000,
          type: "l",
          sleep: 1_000,
          type: "l",
          sleep: 1_300
        ],
        poster: 5.2
      ),
      example(
        "flex",
        [
          sleep: 600,
          type: "jjjjjjjj",
          sleep: 1_000,
          type: "l",
          sleep: 1_000,
          type: "+",
          sleep: 800,
          type: "jjjj",
          sleep: 1_200
        ],
        poster: 4.3
      ),
      example("gauge", [sleep: 400, space: 1, sleep: 5_000, space: 1, sleep: 900], poster: 4.5),
      example("gauges", [sleep: 6_000], poster: 4.0),
      example("hello_world", [sleep: 4_000], poster: 2.0),
      example("hyperlink", [sleep: 4_000], poster: 2.0),
      example("inline", [sleep: 6_000], poster: 4.0),
      example(
        "input_form",
        [
          sleep: 400,
          type_slow: "Douglas",
          tab: 1,
          type_slow: "douglas@elui.sh",
          tab: 1,
          type_slow: "42",
          sleep: 700,
          enter: 1,
          sleep: 2_000
        ],
        poster: 4.4
      ),
      example("layout", [sleep: 4_000], poster: 2.0),
      example(
        "list",
        [
          sleep: 400,
          type: "jjjjjj",
          sleep: 1_000,
          type: String.duplicate("j", 43),
          sleep: 1_000,
          type: String.duplicate("k", 49),
          sleep: 1_000
        ],
        poster: 2.8
      ),
      example("minimal", [sleep: 5_000], poster: 3.0),
      example(
        "modifiers",
        [sleep: 500, type: "jjj", sleep: 900, type: "jj", sleep: 900, type: "kk", sleep: 1_100],
        poster: 3.0
      ),
      example("mouse_drawing", mouse_actions(), poster: 6.8, startup: 3_000),
      example("panic", [sleep: 4_000], poster: 2.0),
      example("popup", [sleep: 600, type: "p", sleep: 2_000, type: "p", sleep: 1_200],
        poster: 1.8
      ),
      example("release_header", [sleep: 4_000], poster: 2.0),
      example(
        "scrollbar",
        [
          sleep: 500,
          type: "f",
          sleep: 900,
          type: "f",
          sleep: 800,
          type: "lllll",
          sleep: 800,
          type: "b",
          sleep: 1_100
        ],
        poster: 3.4
      ),
      example("table", [sleep: 500, type: "jjjj", sleep: 1_200, type: "kk", sleep: 1_200],
        poster: 2.3
      ),
      example(
        "todo_list",
        [
          sleep: 500,
          type: "j",
          space: 1,
          sleep: 700,
          type: "a",
          type_slow: "Publish Elui videos",
          enter: 1,
          sleep: 2_000
        ],
        poster: 4.2
      ),
      example("tracing", [sleep: 1_800, space: 1, sleep: 1_500, space: 1, sleep: 1_900],
        poster: 4.4
      ),
      example(
        "user_input",
        [
          sleep: 400,
          type_slow: "Elui runs on the BEAM",
          enter: 1,
          sleep: 900,
          type_slow: "Messages stay in state",
          enter: 1,
          sleep: 1_800
        ],
        poster: 4.5,
        quit: [key: "Ctrl+["]
      ),
      example(
        "volatility_surface",
        [
          sleep: 500,
          type: "lllll",
          sleep: 800,
          type: "kk",
          sleep: 700,
          type: "++",
          sleep: 800,
          type: "hhh",
          sleep: 1_100
        ],
        poster: 3.7
      ),
      example("weather", [sleep: 4_000], poster: 2.0),
      example("widget_ref_container", [sleep: 6_000], poster: 4.0)
    ]
  end

  defp example(name, actions, opts) do
    %{
      name: name,
      actions: actions,
      env: Keyword.get(opts, :env, %{}),
      peer: Keyword.get(opts, :peer, false),
      poster: Keyword.get(opts, :poster, 2.0),
      quit: Keyword.get(opts, :quit, type: "q"),
      startup: Keyword.get(opts, :startup, 1_500)
    }
  end

  defp mouse_actions do
    [sleep: 500] ++
      stroke([{15, 12}, {15, 28}]) ++
      stroke([{15, 12}, {27, 12}]) ++
      stroke([{15, 20}, {24, 20}]) ++
      stroke([{15, 28}, {27, 28}]) ++
      [space: 1, sleep: 250] ++
      stroke([{35, 12}, {35, 28}, {47, 28}]) ++
      [space: 1, sleep: 250] ++
      stroke([{55, 12}, {55, 28}, {67, 28}, {67, 12}]) ++
      [space: 1, sleep: 250] ++
      stroke([{75, 12}, {87, 12}]) ++
      stroke([{81, 12}, {81, 28}]) ++
      stroke([{75, 28}, {87, 28}]) ++
      [sleep: 1_500]
  end

  defp stroke([first | rest]) do
    [{:mouse, 0, elem(first, 0), elem(first, 1), "M"}] ++
      Enum.map(rest, fn {x, y} -> {:mouse, 32, x, y, "M"} end) ++
      [{:mouse, 0, elem(List.last(rest), 0), elem(List.last(rest), 1), "m"}, {:sleep, 350}]
  end

  defp select_examples!(examples, args) when args in [[], ["--all"]], do: examples

  defp select_examples!(examples, args) do
    names = MapSet.new(args)
    available = MapSet.new(examples, & &1.name)
    unknown = MapSet.difference(names, available) |> MapSet.to_list() |> Enum.sort()

    if unknown != [] do
      raise "unknown example(s): #{Enum.join(unknown, ", ")}"
    end

    Enum.filter(examples, &MapSet.member?(names, &1.name))
  end

  defp record(example, index, total) do
    IO.puts("[#{index}/#{total}] #{example.name}")

    tape_path =
      Path.join(
        System.tmp_dir!(),
        "elui-#{example.name}-#{System.unique_integer([:positive])}.tape"
      )

    File.write!(tape_path, tape(example))
    peer = if example.peer, do: start_peer(), else: nil

    try do
      if peer, do: Process.sleep(700)

      case System.cmd("vhs", [tape_path], cd: @root, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, status} -> raise "VHS failed for #{example.name} (#{status}):\n#{output}"
      end

      create_poster!(example)
      bytes = File.stat!(Path.join(@video_dir, "#{example.name}.mp4")).size
      IO.puts("      ok #{Float.round(bytes / 1_048_576, 2)} MB")
    after
      File.rm(tape_path)
      stop_peer(peer)
    end
  end

  defp tape(example) do
    env_lines = Enum.map(example.env, fn {key, value} -> "Env #{key} #{inspect(value)}" end)

    lines =
      [
        "Require mix",
        "",
        "Output website/videos/#{example.name}.mp4",
        "",
        "Set Shell zsh",
        "Set Width 1440",
        "Set Height 810",
        ~s(Set FontFamily "JetBrainsMono Nerd Font Mono"),
        "Set FontSize 14",
        "Set LineHeight 1.0",
        "Set LetterSpacing 0",
        "Set Padding 14",
        "Set Margin 24",
        ~s(Set MarginFill "#080a07"),
        "Set WindowBar Rings",
        "Set BorderRadius 8",
        "Set Framerate 25",
        "Set TypingSpeed 20ms",
        @theme,
        ""
      ] ++
        env_lines ++
        [
          "",
          "Hide",
          ~s(Type "clear"),
          "Enter",
          "Sleep 100ms",
          ~s(Type "mix run examples/#{example.name}.exs"),
          "Enter",
          "Sleep #{example.startup}ms",
          "Show",
          ""
        ] ++
        action_lines(example.actions) ++
        ["", "Hide"] ++
        action_lines(example.quit) ++
        ["Sleep 300ms", ""]

    Enum.join(lines, "\n")
  end

  defp action_lines(actions) do
    Enum.flat_map(actions, fn
      {:sleep, milliseconds} -> ["Sleep #{milliseconds}ms"]
      {:type, text} -> ["Type #{inspect(text)}"]
      {:type_slow, text} -> ["Type@45ms #{inspect(text)}"]
      {:space, count} -> ["Space #{count}"]
      {:tab, count} -> ["Tab #{count}"]
      {:enter, count} -> ["Enter #{count}"]
      {:key, command} -> [command]
      {:mouse, code, x, y, final} -> ["Ctrl+[", ~s(Type@0ms "[<#{code};#{x};#{y}#{final}")]
    end)
  end

  defp create_poster!(example) do
    video = Path.join(@video_dir, "#{example.name}.mp4")
    poster = Path.join(@poster_dir, "#{example.name}.jpg")
    seek = min(example.poster, max(video_duration(video) - 0.25, 0.0))

    args = [
      "-v",
      "error",
      "-y",
      "-ss",
      to_string(seek),
      "-i",
      video,
      "-frames:v",
      "1",
      "-vf",
      "scale=960:-2",
      "-pix_fmt",
      "yuvj420p",
      "-q:v",
      "3",
      "-update",
      "1",
      poster
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        raise "poster generation failed for #{example.name} (#{status}):\n#{output}"
    end
  end

  defp video_duration(video) do
    args = [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      video
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {output, 0} ->
        {duration, _rest} = output |> String.trim() |> Float.parse()
        duration

      {output, status} ->
        raise "could not read video duration for #{video} (#{status}):\n#{output}"
    end
  end

  defp start_peer do
    executable = System.find_executable("elixir")

    Port.open(
      {:spawn_executable, executable},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args:
          Enum.map(
            [
              "--name",
              "elui_peer@127.0.0.1",
              "--cookie",
              "elui_demo",
              "-e",
              "Process.sleep(:infinity)"
            ],
            &String.to_charlist/1
          )
      ]
    )
  end

  defp stop_peer(nil), do: :ok

  defp stop_peer(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("kill", [Integer.to_string(pid)], stderr_to_stdout: true)
      nil -> :ok
    end

    receive do
      {^port, {:exit_status, _status}} -> :ok
    after
      1_000 -> Port.close(port)
    end
  rescue
    _ -> :ok
  end

  defp ensure_tools! do
    Enum.each(["mix", "elixir", "vhs", "ffmpeg", "ffprobe"], fn executable ->
      unless System.find_executable(executable) do
        raise "required executable not found: #{executable}"
      end
    end)
  end
end

EluiExampleRecorder.main(System.argv())
