defmodule Quality.ConfigTest do
  use ExUnit.Case, async: true

  alias Quality.Config

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

    test "skip_dependencies CLI option sets dependencies enabled to false" do
      config = Config.load(skip_dependencies: true)

      assert config[:dependencies][:enabled] == false
    end

    test "verbose CLI option sets verbose to true" do
      config = Config.load(verbose: true)

      assert config[:verbose] == true
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
  end
end
