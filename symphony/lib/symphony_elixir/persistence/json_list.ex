defmodule SymphonyElixir.Persistence.JsonList do
  @moduledoc false

  use Ecto.Type

  @spec type() :: :map
  def type, do: :map

  @spec cast(term()) :: {:ok, list()} | :error
  def cast(value) when is_list(value), do: {:ok, value}
  def cast(nil), do: {:ok, []}
  def cast(_value), do: :error

  @spec load(term()) :: {:ok, list()} | :error
  def load(value) when is_list(value), do: {:ok, value}
  def load(nil), do: {:ok, []}
  def load(_value), do: :error

  @spec dump(term()) :: {:ok, list()} | :error
  def dump(value) when is_list(value), do: {:ok, value}
  def dump(nil), do: {:ok, []}
  def dump(_value), do: :error
end
