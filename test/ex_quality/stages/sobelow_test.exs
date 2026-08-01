defmodule ExQuality.Stages.SobelowTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stage
  alias ExQuality.Stages.Sobelow

  describe "run/1 - a clean scan" do
    test "passes with no findings" do
      stub_scan(report())

      result = Sobelow.run([])

      assert result.name == "Sobelow"
      assert result.status == :ok
      assert result.summary == "No findings"
      assert result.stats.finding_count == 0
      assert Stage.findings(result) == []
      assert is_integer(result.duration_ms)
    end
  end

  describe "run/1 - blocking findings" do
    setup do
      stub_scan(
        report(
          high: [entry("Config.CSRF: Missing CSRF Protections", "lib/web/router.ex", 10)],
          medium: [entry("XSS.Raw: XSS", "lib/web/page_html.ex", 4, "@conn")]
        )
      )

      :ok
    end

    test "fails and counts them by confidence" do
      result = Sobelow.run([])

      assert result.status == :error
      assert result.summary == "2 blocking findings (1 high, 1 medium)"
      assert result.stats.blocking_count == 2
      assert result.stats.informational_count == 0
      assert result.stats.blocking_by_confidence == [{"high", 1}, {"medium", 1}]
    end

    test "renders them as findings" do
      assert [xss, csrf] = Stage.findings(Sobelow.run([]))

      assert %ExQuality.Finding{
               file: "lib/web/page_html.ex",
               line: 4,
               app: nil,
               severity: :error,
               check: "XSS.Raw"
             } = xss

      assert xss.message == "XSS (medium confidence): @conn"
      assert csrf.check == "Config.CSRF"
      assert csrf.message == "Missing CSRF Protections (high confidence)"
      assert csrf.raw =~ "Config.CSRF"
    end
  end

  describe "run/1 - findings below the threshold" do
    setup do
      stub_scan(
        report(
          low: [
            entry("Config.HTTPS: HTTPS Not Enabled", "config/prod.exs", 3),
            entry("Config.CSP: Missing Content-Security-Policy", "lib/web/endpoint.ex", 9)
          ]
        )
      )

      :ok
    end

    test "passes and reports them as a count only" do
      result = Sobelow.run([])

      assert result.status == :ok
      assert result.summary == "No blocking findings, 2 informational not shown"
      assert result.stats.finding_count == 2
      assert result.stats.blocking_count == 0
      assert Stage.findings(result) == []
    end

    test "renders them when asked to" do
      result = Sobelow.run(sobelow: [show_informational: true])

      assert result.status == :ok
      assert result.summary == "No blocking findings, 2 informational"
      assert [https, csp] = Stage.findings(result)
      assert https.severity == :info
      assert csp.severity == :info
    end

    test "renders them under --verbose" do
      result = Sobelow.run(verbose: true)

      assert length(Stage.findings(result)) == 2
    end
  end

  describe "run/1 - the exit threshold" do
    test "blocks on high and medium by default" do
      stub_scan(report(medium: [entry("XSS.Raw: XSS", "lib/a.ex", 1)]))

      assert Sobelow.run([]).status == :error
    end

    test "takes a default from .quality.exs when there is no .sobelow-conf" do
      stub_scan(report(medium: [entry("XSS.Raw: XSS", "lib/a.ex", 1)]))

      result = Sobelow.run(sobelow: [exit: "high"])

      assert result.status == :ok
      assert result.summary == "No blocking findings, 1 informational not shown"
    end

    test "lets .sobelow-conf win over .quality.exs" do
      root = conf_dir(exit: "low", format: "txt")
      stub_umbrella(%{web: root})
      stub_scan(report(low: [entry("Config.CSP: Missing CSP", "lib/a.ex", 1)]))

      result = Sobelow.run(sobelow: [exit: "high"])

      assert result.status == :error
      assert result.summary == "1 blocking finding (1 low)"
    end

    test "blocks on nothing when .sobelow-conf asks for no exit status" do
      root = conf_dir(exit: "None")
      stub_umbrella(%{web: root})
      stub_scan(report(high: [entry("Config.CSRF: Missing CSRF", "lib/a.ex", 1)]))

      result = Sobelow.run([])

      assert result.status == :ok
      assert result.summary == "No blocking findings, 1 informational not shown"
    end
  end

  describe "run/1 - the command" do
    test "asks for JSON in a file and skips the version check" do
      System
      |> expect(:cmd, fn "mix", args, opts ->
        assert ["sobelow", "--format", "json", "--private", "--out", out] = args
        assert opts[:env] == [{"MIX_ENV", "dev"}]
        File.write!(out, report())
        {"", 0}
      end)

      assert Sobelow.run([]).status == :ok
    end

    test "passes through what .sobelow-conf says to scan" do
      root =
        conf_dir(
          skip: true,
          router: "lib/web/router.ex",
          threshold: "medium",
          ignore: ["XSS.Raw", "Traversal"],
          ignore_files: ["lib/generated.ex", ""],
          format: "txt",
          verbose: true
        )

      stub_umbrella(%{web: root})

      System
      |> expect(:cmd, fn "mix", args, _opts ->
        write_report(args, report())
        {"", 0}
      end)

      assert Sobelow.run([]).status == :ok
      assert_received {:sobelow_args, args}

      assert ["--root", ^root | rest] = Enum.drop(args, 6)

      assert rest == [
               "--skip",
               "--router",
               "lib/web/router.ex",
               "--threshold",
               "medium",
               "--ignore",
               "XSS.Raw,Traversal",
               "--ignore-files",
               "lib/generated.ex"
             ]
    end
  end

  describe "run/1 - umbrellas" do
    test "scans each app that could have something to report, tagging findings" do
      stub_umbrella(%{web: "apps/web", core: "apps/core", admin: "apps/admin"}, %{
        web: [{:phoenix, "~> 1.7"}, {:sobelow, "~> 0.13", only: :dev}],
        core: [{:ecto, "~> 3.0"}],
        admin: [{:phoenix, "~> 1.7"}]
      })

      System
      |> stub(:cmd, fn "mix", args, _opts ->
        root = root_of(args)
        write_report(args, report(high: [entry("XSS.Raw: XSS", "#{root}/lib/a.ex", 2)]))
        {"", 0}
      end)

      result = Sobelow.run([])

      assert result.status == :error
      assert [admin, web] = Stage.findings(result)
      assert admin.app == :admin
      assert admin.file == "apps/admin/lib/a.ex"
      assert web.app == :web
      refute :core in Enum.map(Stage.findings(result), & &1.app)
    end

    test "does not run at all when no app uses sobelow or phoenix" do
      stub_umbrella(%{core: "apps/core"}, %{core: [{:ecto, "~> 3.0"}]})

      System
      |> expect(:cmd, fn "mix", args, _opts ->
        refute "--root" in args
        write_report(args, report())
        {"", 0}
      end)

      assert Sobelow.run([]).status == :ok
    end
  end

  describe "run/1 - a scan that produced no report" do
    test "fails with the tool's output rather than reporting a clean scan" do
      System
      |> expect(:cmd, fn "mix", _args, _opts ->
        {"** (Mix) The task \"sobelow\" could not be found", 1}
      end)

      result = Sobelow.run([])

      assert result.status == :error
      assert result.summary == "Sobelow did not produce a report"
      assert result.output =~ "could not be found"
      assert Stage.findings(result) == []
    end

    test "names the apps it failed for" do
      stub_umbrella(%{web: "apps/web"}, %{web: [{:phoenix, "~> 1.7"}]})

      System
      |> expect(:cmd, fn "mix", _args, _opts -> {"boom", 1} end)

      assert Sobelow.run([]).summary == "Sobelow did not produce a report (web)"
    end

    test "reads JSON from stdout when the tool is too old for --out" do
      System
      |> expect(:cmd, fn "mix", _args, _opts ->
        {report(high: [entry("XSS.Raw: XSS", "lib/a.ex", 1)]), 0}
      end)

      result = Sobelow.run([])

      assert result.status == :error
      assert [%{file: "lib/a.ex"}] = Stage.findings(result)
    end
  end

  describe "run/1 - findings the tool could not place" do
    test "leaves the line unset rather than reporting line 0" do
      stub_scan(report(high: [entry("Config.Secrets: Hardcoded Secret", "config/prod.exs", 0)]))

      assert [finding] = Stage.findings(Sobelow.run([]))
      assert finding.line == nil
    end

    test "keeps a type that names no check as the message" do
      stub_scan(report(high: [entry("Something happened", "lib/a.ex", 1)]))

      assert [finding] = Stage.findings(Sobelow.run([]))
      assert finding.check == nil
      assert finding.message == "Something happened (high confidence)"
    end
  end

  # Stubs System.cmd to write the given report wherever `--out` points, which
  # is what sobelow itself does.
  defp stub_scan(json) do
    System
    |> stub(:cmd, fn "mix", args, _opts ->
      write_report(args, json)
      {"", 0}
    end)
  end

  defp write_report(args, json) do
    send(self(), {:sobelow_args, args})
    index = Enum.find_index(args, &(&1 == "--out"))
    File.write!(Enum.at(args, index + 1), json)
    :ok
  end

  defp root_of(args) do
    case Enum.find_index(args, &(&1 == "--root")) do
      nil -> "."
      index -> Enum.at(args, index + 1)
    end
  end

  defp stub_umbrella(apps, deps \\ nil) do
    deps = deps || Map.new(apps, fn {app, _path} -> {app, [{:phoenix, "~> 1.7"}]} end)

    ExQuality.Umbrella
    |> stub(:apps_paths, fn -> apps end)
    |> stub(:app_deps, fn -> deps end)
  end

  # A real directory holding a real .sobelow-conf, since the stage reads the
  # project's own file rather than being told its contents.
  defp conf_dir(conf) do
    dir = Path.join(System.tmp_dir!(), "ex_quality-conf-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, ".sobelow-conf"), inspect(conf))
    on_exit(fn -> File.rm_rf!(dir) end)

    dir
  end

  defp report(findings \\ []) do
    high = Keyword.get(findings, :high, [])
    medium = Keyword.get(findings, :medium, [])
    low = Keyword.get(findings, :low, [])

    Jason.encode!(%{
      "findings" => %{
        "high_confidence" => high,
        "medium_confidence" => medium,
        "low_confidence" => low
      },
      "total_findings" => length(high) + length(medium) + length(low),
      "sobelow_version" => "0.13.0"
    })
  end

  defp entry(type, file, line, variable \\ nil) do
    %{"type" => type, "file" => file, "line" => line, "variable" => variable}
  end
end
