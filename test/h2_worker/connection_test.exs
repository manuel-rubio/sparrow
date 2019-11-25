defmodule Sparrow.H2Worker.ConnectionTest do
  alias Helpers.SetupHelper, as: Tools
  use ExUnit.Case
  use Quixir

  import Mox
  setup :set_mox_global
  setup :verify_on_exit!

  alias Sparrow.H2Worker.Config
  alias Sparrow.H2Worker.Request, as: OuterRequest
  alias Sparrow.H2Worker.State

  @repeats 2

  setup do
    :set_mox_from_context
    :verify_on_exit!
    auth =
      Sparrow.H2Worker.Authentication.CertificateBased.new(
        "path/to/exampleName.pem",
        "path/to/exampleKey.pem"
      )

    real_auth =
      Sparrow.H2Worker.Authentication.CertificateBased.new(
        "test/priv/certs/Certificates1.pem",
        "test/priv/certs/key.pem"
      )

    {:ok, connection_ref: pid(), auth: auth, real_auth: real_auth}
  end

  test "server receives connection backoff", context do
    ptest [
            domain: string(min: 3, max: 10, chars: ?a..?z),
            port: int(min: 0, max: 65_535),
            reason: atom(min: 2, max: 5),
            tls_options: list(of: atom(), min: 0, max: 3)
          ],
          repeat_for: @repeats do
      conn_pid = pid()
      me = self()

       Sparrow.H2ClientAdapter.Mock
       |> expect(:open, 1, fn _, _, _ -> (send(me, {:first_connection_failure, Time.utc_now}); {:error, reason}) end)
       |> expect(:open, 4, fn _, _, _ -> {:error, reason} end)
       |> expect(:open, 1, fn _, _, _ -> (send(me, {:first_connection_success, Time.utc_now}); {:ok, conn_pid}) end)
       |> stub(:ping, fn _ -> :ok end)
       |> stub(:post, fn _, _, _, _, _ -> {:error, :something} end)
       |> stub(:get_response, fn _, _ -> {:error, :not_ready} end)
       |> stub(:close, fn _ -> :ok end)

       config =
          Config.new(%{
            domain: domain,
            port: port,
            authentication: context[:auth],
            tls_options: tls_options
          })

       pid = start_supervised(Tools.h2_worker_spec(config))

       assert_receive {:first_connection_failure, f}, 200
       assert_receive {:first_connection_success, s}, 2_000
       assert_in_delta 1800, 1900, Time.diff(s, f, :millisecond)
    end
  end

  defp pid do
    spawn(fn -> :timer.sleep(5_000) end)
  end
end