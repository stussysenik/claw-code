defmodule ClawCode.EnvLoaderTest do
  use ExUnit.Case, async: false

  alias ClawCode.EnvLoader

  test "parse ignores comments and preserves quoted values" do
    contents = """
    # comment
    export FOO=bar
    BAR="quoted value"
    BAZ='single quoted'
    EMPTY=
    """

    assert EnvLoader.parse(contents) == [
             {"FOO", "bar"},
             {"BAR", "quoted value"},
             {"BAZ", "single quoted"},
             {"EMPTY", ""}
           ]
  end

  test "load prefers existing process env over .env.local values" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-env-loader-#{System.unique_integer([:positive])}")

    File.rm_rf(root)
    File.mkdir_p!(root)

    File.write!(
      Path.join(root, ".env.local"),
      """
      FOO=from-file
      BAR=bar-file
      """
    )

    previous_foo = System.get_env("FOO")
    previous_bar = System.get_env("BAR")
    System.put_env("FOO", "already-set")
    System.delete_env("BAR")

    on_exit(fn ->
      restore_env("FOO", previous_foo)
      restore_env("BAR", previous_bar)
      File.rm_rf(root)
    end)

    assert :ok = EnvLoader.load(cwd: root)
    assert System.get_env("FOO") == "already-set"
    assert System.get_env("BAR") == "bar-file"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
