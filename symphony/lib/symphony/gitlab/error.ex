defmodule Symphony.GitLab.Error do
  @moduledoc """
  Normalized GitLab REST client error.
  """

  defexception [:type, :status, :message, :retry_after]

  @type error_type ::
          :unauthorized
          | :forbidden
          | :not_found
          | :rate_limited
          | :validation_error
          | :network_error
          | :server_error
          | :invalid_config
          | :unexpected_response

  @type t :: %__MODULE__{
          type: error_type(),
          status: integer() | nil,
          message: String.t(),
          retry_after: String.t() | nil
        }

  @impl true
  def exception(opts) do
    %__MODULE__{
      type: Keyword.fetch!(opts, :type),
      status: Keyword.get(opts, :status),
      message: Keyword.get(opts, :message, "GitLab request failed"),
      retry_after: Keyword.get(opts, :retry_after)
    }
  end
end
