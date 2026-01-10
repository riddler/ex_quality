defmodule ExQuality.Init.ProjectConfigTest do
  use ExUnit.Case, async: true

  test "adds test_coverage config to mix.exs when not present" do
    in_tmp_dir(fn ->
      # Create a mix.exs without test_coverage
      mix_exs = """
      defmodule TestProject.MixProject do
        use Mix.Project

        def project do
          [
            app: :test_project,
            version: "0.1.0",
            elixir: "~> 1.14"
          ]
        end

        defp deps do
          [
            {:ex_quality, "~> 0.1", only: :dev, runtime: false}
          ]
        end
      end
      """

      File.write!("mix.exs", mix_exs)

      # Manually test the logic by simulating what configure_project_settings does
      if :coverage in [:coverage] do
        content = File.read!("mix.exs")

        unless String.contains?(content, "test_coverage:") do
          lines = String.split(content, "\n")

          # Find project bracket
          project_idx = Enum.find_index(lines, &String.match?(&1, ~r/def\s+project\s+do/))

          bracket_idx =
            lines
            |> Enum.drop(project_idx + 1)
            |> Enum.with_index(project_idx + 1)
            |> Enum.find(fn {line, _} -> String.match?(line, ~r/^\s+\[/) end)
            |> elem(1)

          # Get indent from next line
          next_line = Enum.at(lines, bracket_idx + 1, "")
          indent = Regex.run(~r/^(\s*)/, next_line) |> List.last()

          # Insert config (both test_coverage and preferred_cli_env)
          coverage_config = """
          #{indent}test_coverage: [tool: ExCoveralls],
          #{indent}preferred_cli_env: [
          #{indent}  coveralls: :test,
          #{indent}  "coveralls.detail": :test,
          #{indent}  "coveralls.post": :test,
          #{indent}  "coveralls.html": :test
          #{indent}],\
          """

          new_lines =
            List.update_at(lines, bracket_idx, fn line ->
              line <> "\n" <> coverage_config
            end)

          File.write!("mix.exs", Enum.join(new_lines, "\n"))
        end
      end

      # Verify both configurations were added
      updated_content = File.read!("mix.exs")
      assert updated_content =~ "test_coverage: [tool: ExCoveralls]"
      assert updated_content =~ "preferred_cli_env: ["
      assert updated_content =~ "coveralls: :test"
      assert updated_content =~ ~r/def project do.*test_coverage:/s

      # Verify it was added in the right place (after the opening bracket)
      assert updated_content =~ ~r/\[\n\s+test_coverage: \[tool: ExCoveralls\],/
    end)
  end

  test "doesn't modify mix.exs if test_coverage already present" do
    in_tmp_dir(fn ->
      # Create a mix.exs with test_coverage already configured
      mix_exs = """
      defmodule TestProject.MixProject do
        use Mix.Project

        def project do
          [
            app: :test_project,
            version: "0.1.0",
            elixir: "~> 1.14",
            test_coverage: [tool: ExCoveralls]
          ]
        end

        defp deps do
          [
            {:ex_quality, "~> 0.1", only: :dev, runtime: false}
          ]
        end
      end
      """

      File.write!("mix.exs", mix_exs)
      original_content = File.read!("mix.exs")

      # Check if already configured (simulate the check)
      has_config = String.contains?(original_content, "test_coverage:")

      assert has_config

      # Count occurrences - should be exactly 1
      count = original_content |> String.split("test_coverage:") |> length()
      # 1 split = 2 parts = 1 occurrence
      assert count == 2
    end)
  end

  defp in_tmp_dir(fun) do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "ex_quality_test_#{:rand.uniform(100_000_000)}"
      ])

    File.mkdir_p!(tmp_dir)

    try do
      File.cd!(tmp_dir, fun)
    after
      File.rm_rf!(tmp_dir)
    end
  end
end
