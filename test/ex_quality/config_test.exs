defmodule ExQuality.ConfigTest do
  use ExUnit.Case, async: true

  alias ExQuality.Config

  describe "load/1" do
    test "loads default configuration" do
      config = Config.load()

      assert is_list(config)
      assert config[:quick] == false
      assert config[:compile][:warnings_as_errors] == true
      assert config[:credo][:enabled] == :auto
      assert config[:credo][:strict] == true
      assert config[:credo][:all] == false
    end

    test "merges CLI options with defaults" do
      config = Config.load(quick: true)

      assert config[:quick] == true
      # Other defaults should still be present
      assert config[:credo][:strict] == true
    end

    test "skip_dialyzer CLI option sets dialyzer enabled to false" do
      config = Config.load(skip_dialyzer: true)

      assert config[:dialyzer][:enabled] == false
    end

    test "skip_credo CLI option sets credo enabled to false" do
      config = Config.load(skip_credo: true)

      assert config[:credo][:enabled] == false
    end

    test "skip_doctor CLI option sets doctor enabled to false" do
      config = Config.load(skip_doctor: true)

      assert config[:doctor][:enabled] == false
    end

    test "skip_gettext CLI option sets gettext enabled to false" do
      config = Config.load(skip_gettext: true)

      assert config[:gettext][:enabled] == false
    end

    test "skip_sobelow CLI option sets sobelow enabled to false" do
      config = Config.load(skip_sobelow: true)

      assert config[:sobelow][:enabled] == false
      assert Config.skip_reason(config, :sobelow) == "--skip-sobelow"
    end

    test "skip_dependencies CLI option sets dependencies enabled to false" do
      config = Config.load(skip_dependencies: true)

      assert config[:dependencies][:enabled] == false
    end

    test "verbose CLI option sets verbose to true" do
      config = Config.load(verbose: true)

      assert config[:verbose] == true
    end

    test "test_args CLI option sets test args" do
      config = Config.load(test_args: ["--only", "integration"])

      assert config[:test][:args] == ["--only", "integration"]
    end

    test "includes auto-detected tool availability" do
      config = Config.load()

      # Should have availability info from auto-detection
      assert Keyword.has_key?(config, :credo)
      assert Keyword.has_key?(config, :dialyzer)
      assert Keyword.has_key?(config, :doctor)

      # Availability should be boolean
      credo_config = config[:credo]
      assert is_boolean(credo_config[:available])
    end

    test "handles multiple CLI options together" do
      config = Config.load(quick: true, skip_credo: true, verbose: true)

      assert config[:quick] == true
      assert config[:credo][:enabled] == false
      assert config[:verbose] == true
    end
  end

  describe "stage_enabled?/2" do
    test "returns false when enabled is explicitly false" do
      config = [credo: [enabled: false, available: true]]

      refute Config.stage_enabled?(config, :credo)
    end

    test "returns true when enabled is explicitly true" do
      config = [credo: [enabled: true, available: false]]

      assert Config.stage_enabled?(config, :credo)
    end

    test "returns availability status when enabled is :auto" do
      config_available = [credo: [enabled: :auto, available: true]]
      config_unavailable = [credo: [enabled: :auto, available: false]]

      assert Config.stage_enabled?(config_available, :credo)
      refute Config.stage_enabled?(config_unavailable, :credo)
    end

    test "defaults to true for available when not specified" do
      config = [credo: [enabled: :auto]]

      assert Config.stage_enabled?(config, :credo)
    end

    test "defaults to :auto for enabled when not specified" do
      config = [credo: [available: false]]

      refute Config.stage_enabled?(config, :credo)
    end

    test "returns false for missing stage configuration" do
      config = []

      # When enabled is not specified, it defaults to :auto
      # When available is not specified, it defaults to true
      # So :auto + true = true
      assert Config.stage_enabled?(config, :unknown_stage)
    end
  end

  describe "skip_reason/2" do
    test "returns nil when the stage will run" do
      config = [credo: [enabled: :auto, available: true]]

      assert Config.skip_reason(config, :credo) == nil
    end

    test "names the CLI switch that disabled the stage" do
      config = Config.load(skip_dialyzer: true)

      assert Config.skip_reason(config, :dialyzer) == "--skip-dialyzer"
    end

    test "names the config file when it disabled the stage" do
      config = [credo: [enabled: false, disabled_by: :config]]

      assert Config.skip_reason(config, :credo) == "disabled in .quality.exs"
    end

    test "names the missing package when the tool is not installed" do
      config = [dialyzer: [enabled: :auto, available: false]]

      assert Config.skip_reason(config, :dialyzer) == ":dialyxir not installed"
    end

    test "falls back to a bare reason for a stage with no package" do
      config = [dependencies: [enabled: :auto, available: false]]

      assert Config.skip_reason(config, :dependencies) == "disabled"
    end
  end

  describe "skip/2" do
    test "returns nil when the stage will run" do
      config = [credo: [enabled: :auto, available: true]]

      assert Config.skip(config, :credo) == nil
    end

    test "a CLI switch is a run-level skip: a full run without it closes the gap" do
      config = Config.load(skip_dialyzer: true)

      assert Config.skip(config, :dialyzer) == {"--skip-dialyzer", :run}
    end

    test "the generic --skip switch is a run-level skip too" do
      config = [nullability: [enabled: false, disabled_by: {:cli, "--skip nullability"}]]

      assert Config.skip(config, :nullability) == {"--skip nullability", :run}
    end

    test "a profile's allow-list is a run-level skip" do
      config = Config.apply_profile([profiles: [loop: [stages: [:format]]]], "loop")

      assert Config.skip(config, :dialyzer) == {"not in profile :loop", :run}
    end

    test "the config file is a project-level skip: a fuller run cannot close it" do
      config = [credo: [enabled: false, disabled_by: :config]]

      assert Config.skip(config, :credo) == {"disabled in .quality.exs", :project}
    end

    test "a missing tool is a project-level skip" do
      config = [dialyzer: [enabled: :auto, available: false]]

      assert Config.skip(config, :dialyzer) == {":dialyxir not installed", :project}
    end
  end

  describe "apply_profile/2" do
    @profiles [
      profiles: [
        loop: [stages: [:format, :compile, :credo], test: [scope: :changed]],
        gate: []
      ]
    ]

    test "returns the config untouched with no profile" do
      assert Config.apply_profile(@profiles, nil) == @profiles
    end

    test "merges the profile's options" do
      config = Config.apply_profile(@profiles, "loop")

      assert config[:profile] == :loop
      assert config[:test][:scope] == :changed
    end

    test "keeps options the profile does not mention" do
      config = Config.apply_profile([credo: [strict: true]] ++ @profiles, "loop")

      assert config[:credo][:strict] == true
    end

    test "skips every stage the profile leaves out, naming the profile" do
      config = Config.apply_profile(@profiles, "loop")

      assert Config.skip_reason(config, :dialyzer) == "not in profile :loop"
      assert Config.skip_reason(config, :sobelow) == "not in profile :loop"
      assert Config.skip_reason(config, :test) == "not in profile :loop"
    end

    test "runs the stages the profile lists" do
      config = Config.apply_profile(@profiles, "loop")

      assert Config.skip_reason(config, :format) == nil
      assert Config.skip_reason(config, :compile) == nil
      assert Config.skip_reason(config, :credo) == nil
    end

    test "skips a custom stage the profile leaves out" do
      config =
        @profiles ++ [custom: [[key: :house_rules, name: "House rules", command: "true"]]]

      config = Config.apply_profile(config, "loop")

      assert Config.skip_reason(config, :house_rules) == "not in profile :loop"
    end

    test "a profile with no stages: narrows nothing" do
      config = Config.apply_profile(@profiles, "gate")

      assert config[:profile] == :gate
      assert Config.skip_reason(config, :dialyzer) == nil
    end

    test "an unknown profile fails the run and lists the known ones" do
      assert_raise Mix.Error, ~r/Unknown --profile "lop".*:loop, :gate/s, fn ->
        Config.apply_profile(@profiles, "lop")
      end
    end

    test "an unknown profile says so when none are configured" do
      assert_raise Mix.Error, ~r/No profiles are configured/, fn ->
        Config.apply_profile([], "loop")
      end
    end

    test "a malformed profiles: key fails the run" do
      assert_raise Mix.Error, ~r/profiles: in .quality.exs must be a keyword list/, fn ->
        Config.apply_profile([profiles: ["loop"]], "loop")
      end
    end

    test "a malformed stages: list fails the run" do
      assert_raise Mix.Error, ~r/stages: in profile :loop must be a list/, fn ->
        Config.apply_profile([profiles: [loop: [stages: :credo]]], "loop")
      end
    end
  end

  describe "load/1 with the loop switches" do
    test "test scope defaults to :all" do
      assert Config.load()[:test][:scope] == :all
      assert Config.load()[:test][:base_ref] == nil
    end

    test "--test-scope sets the scope" do
      assert Config.load(test_scope: "changed")[:test][:scope] == :changed
      assert Config.load(test_scope: "all")[:test][:scope] == :all

      assert Config.load(test_scope: "test/**/*_test.exs")[:test][:scope] ==
               {:glob, "test/**/*_test.exs"}
    end

    test "--test-scope does not clobber test args" do
      config = Config.load(test_scope: "changed", test_args: ["--seed", "0"])

      assert config[:test][:scope] == :changed
      assert config[:test][:args] == ["--seed", "0"]
    end

    test "a bad --test-scope fails the run" do
      assert_raise Mix.Error, ~r/Invalid --test-scope/, fn ->
        Config.load(test_scope: "")
      end
    end

    test "--until-first-failure is carried on the config" do
      assert Config.load()[:until_first_failure] == nil
      assert Config.load(until_first_failure: true)[:until_first_failure] == true
    end
  end

  describe "configuration merging" do
    test "deep merges nested keyword lists" do
      config = Config.load()

      # Verify that nested configs are properly merged
      # Defaults should have credo.strict = true
      assert config[:credo][:strict] == true
      assert config[:credo][:enabled] == :auto
    end

    test "CLI options override file config and defaults" do
      # Even if a file config exists, CLI should win
      config = Config.load(skip_credo: true)

      assert config[:credo][:enabled] == false
    end

    test "preserves stage-specific options during merge" do
      config = Config.load()

      # Verify various stage options are present
      assert config[:compile][:warnings_as_errors] == true
      assert config[:dependencies][:check_unused] == true
      assert config[:doctor][:summary_only] == false
    end
  end

  describe "auto-detection integration" do
    test "includes audit_available for dependencies stage" do
      config = Config.load()

      deps_config = config[:dependencies]
      assert Keyword.has_key?(deps_config, :audit_available)
      assert is_boolean(deps_config[:audit_available])
    end

    test "includes coverage_available for test stage" do
      config = Config.load()

      test_config = config[:test]
      assert Keyword.has_key?(test_config, :coverage_available)
      assert is_boolean(test_config[:coverage_available])
    end
  end

  describe "config_path/2" do
    @describetag :tmp_dir

    test "reads the project's own file", %{tmp_dir: tmp_dir} do
      child = write_config(tmp_dir, "apps/core")
      root = write_config(tmp_dir, "root")

      assert Config.config_path(child, root) == Path.join(child, ".quality.exs")
    end

    test "falls back to the umbrella root's file", %{tmp_dir: tmp_dir} do
      child = Path.join(tmp_dir, "apps/core")
      root = write_config(tmp_dir, "root")

      assert Config.config_path(child, root) == Path.join(root, ".quality.exs")
    end

    test "returns nil when neither root has one", %{tmp_dir: tmp_dir} do
      assert Config.config_path(tmp_dir, nil) == nil
    end

    test "handles a project that is its own root", %{tmp_dir: tmp_dir} do
      root = write_config(tmp_dir, "single")

      assert Config.config_path(root, root) == Path.join(root, ".quality.exs")
    end
  end

  describe "config_path/0" do
    test "resolves the roots from the current project" do
      # This project has no .quality.exs of its own, and is not in an umbrella.
      assert Config.config_path() == nil
    end
  end

  describe "defaults" do
    test "quick mode defaults to false" do
      config = Config.load()

      assert config[:quick] == false
    end

    test "all stages default to :auto enabled" do
      config = Config.load()

      assert config[:credo][:enabled] == :auto
      assert config[:dialyzer][:enabled] == :auto
      assert config[:doctor][:enabled] == :auto
      assert config[:gettext][:enabled] == :auto
      assert config[:dependencies][:enabled] == :auto
    end

    test "credo strict mode defaults to true" do
      config = Config.load()

      assert config[:credo][:strict] == true
    end

    test "compile warnings_as_errors defaults to true" do
      config = Config.load()

      assert config[:compile][:warnings_as_errors] == true
    end

    test "compile force defaults to false" do
      config = Config.load()

      assert config[:compile][:force] == false
    end
  end

  defp write_config(tmp_dir, path) do
    dir = Path.join(tmp_dir, path)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, ".quality.exs"), "[]")
    dir
  end
end
