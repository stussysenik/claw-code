ExUnit.start()

session_root =
  Path.join(System.tmp_dir!(), "claw-code-test-#{System.unique_integer([:positive])}")

Application.put_env(:claw_code, :session_root, session_root)
