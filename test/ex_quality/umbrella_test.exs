defmodule ExQuality.UmbrellaTest do
  use ExUnit.Case, async: true

  doctest ExQuality.Umbrella

  alias ExQuality.Umbrella

  @apps %{web: "apps/web", core: "apps/core"}

  describe "umbrella?/0" do
    test "is false for this single-app project" do
      refute Umbrella.umbrella?()
    end
  end

  describe "apps_paths/0" do
    test "is empty for a single-app project" do
      assert Umbrella.apps_paths() == %{}
    end
  end

  describe "app_for_path/2" do
    test "returns the app whose directory contains the path" do
      assert Umbrella.app_for_path("apps/web/lib/user.ex", @apps) == :web
      assert Umbrella.app_for_path("apps/core/test/thing_test.exs", @apps) == :core
    end

    test "returns nil for a path outside every app" do
      assert Umbrella.app_for_path("lib/root.ex", @apps) == nil
      assert Umbrella.app_for_path("mix.exs", @apps) == nil
    end

    test "does not match an app whose name is a prefix of a directory" do
      apps = %{ui: "apps/ui"}

      assert Umbrella.app_for_path("apps/ui_web/lib/page.ex", apps) == nil
    end

    test "returns nil for a nil path" do
      assert Umbrella.app_for_path(nil, @apps) == nil
    end

    test "returns nil when there are no apps" do
      assert Umbrella.app_for_path("lib/user.ex") == nil
    end
  end

  describe "child_deps/0" do
    test "is empty for a single-app project" do
      assert Umbrella.child_deps() == []
    end

    test "reset_cache/0 always succeeds" do
      assert Umbrella.reset_cache() == :ok
      assert Umbrella.child_deps() == []
    end
  end

  describe "app_deps/0" do
    test "is empty for a single-app project" do
      assert Umbrella.app_deps() == %{}
    end
  end
end
