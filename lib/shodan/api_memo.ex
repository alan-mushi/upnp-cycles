defmodule Shodan.APIMemo do
  use Agent

  def start_link(_state) do
    Agent.start_link(fn -> nil end, name: APIMemo)
  end

  def get() do
    Agent.get(APIMemo, & &1)
  end

  def update(new_state) do
    Agent.update(APIMemo, fn _state -> new_state end)
  end
end
