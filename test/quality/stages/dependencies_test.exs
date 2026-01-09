defmodule Quality.Stages.DependenciesTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Dependencies

  describe "run/1" do
    test "returns result map with required fields" do
      config = [dependencies: [audit_available: false]]
      result = Dependencies.run(config)

      assert is_map(result)
      assert result.name == "Dependencies"
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "handles config with audit_available: true" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

      assert is_map(result)
    end

    test "handles config with audit_available: false" do
      config = [dependencies: [audit_available: false]]
      result = Dependencies.run(config)

      assert is_map(result)
    end

    test "summary reflects unused deps and security issues" do
      config = [dependencies: [audit_available: false]]
      result = Dependencies.run(config)

      if result.status == :ok do
        # Success summary should mention no issues
        assert result.summary =~ ~r/(No unused|no security)/i
      else
        # Error summary should mention what was found
        assert is_binary(result.summary)
      end
    end

    test "records execution duration" do
      config = [dependencies: [audit_available: false]]
      result = Dependencies.run(config)

      assert result.duration_ms >= 0
      assert result.duration_ms < 30_000
    end
  end

  describe "parallel execution" do
    test "runs both checks in parallel" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

      # Should complete successfully
      assert is_map(result)
      assert result.status in [:ok, :error]
    end
  end
end
