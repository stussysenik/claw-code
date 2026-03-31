defmodule ClawCode do
  @version "0.1.0"

  def version, do: @version
  def root, do: File.cwd!()
end
