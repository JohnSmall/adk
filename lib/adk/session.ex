defmodule ADK.Session do
  @moduledoc """
  Represents a series of interactions between a user and agents.

  A session holds state (scoped by app/user/session/temp prefixes),
  a list of events, and identity information.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          app_name: String.t(),
          user_id: String.t(),
          state: map(),
          events: [ADK.Event.t()],
          last_update_time: DateTime.t()
        }

  @enforce_keys [:id, :app_name, :user_id]
  defstruct [
    :id,
    :app_name,
    :user_id,
    state: %{},
    events: [],
    last_update_time: nil
  ]
end
