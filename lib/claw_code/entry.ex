defmodule ClawCode.Entry do
  @enforce_keys [:kind, :name, :source_hint, :responsibility]
  defstruct [:kind, :name, :source_hint, :responsibility]
end
