defmodule BroadwayHelper do
  alias Broadway.Message

  # Wrapper, only executes `f` if the message status is :ok (i.e. all is good) or return a default value (nil if not specified)
  def run_if_status_is_ok(m, f, opts), do: run_if_status_is_ok(m, f, opts, nil)
  def run_if_status_is_ok(%Message{status: :ok} = m, f, opts, default), do: f.(m, opts, default)
  def run_if_status_is_ok(%Message{} = m, _f, _opts, default), do: {m, default}

  def transform(%Host{} = host, _opts) do
    %Message{
      data: {host, nil},
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def ack(:ack_id, _success, _fail), do: :ok

  def transform_and_push_message(broadway, %Host{} = event) do
    Broadway.push_messages(broadway, [transform(event, [])])
  end

  def transform_and_push_messages(broadway, events) when is_list(events) do
    Broadway.push_messages(broadway, Enum.map(events, &transform(&1, [])))
  end

  def extract_status(%Message{} = m) do
    case Map.get(m, :status) do
      {_, {reason, info}} -> Map.put(%{}, reason, inspect(info)) # inspect info otherwise we have to deal with tuples and Repo.preload() breaks
      :ok -> %{ok: :ok}
      _ -> %{failed_unknown_reason: inspect(m)}
    end
  end

  def one_of_our_ips(%Message{} = m, %Host{ip: ip}, nil) do
    case IPUtils.one_of_our_ips?(ip) do
      true -> Message.failed(m, {:one_of_our_ips, nil})
      _ -> m
    end
  end

  def extract_failed_code(%Message{status: {:failed, res}}), do: res
end
