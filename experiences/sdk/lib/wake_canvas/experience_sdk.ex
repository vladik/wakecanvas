defmodule WakeCanvas.ExperienceSDK do
  @moduledoc """
  Public contracts shared by WakeCanvas and independently built Experiences.

  Experience projects must not depend on the WakeCanvas platform application.
  This SDK is the complete supported in-VM integration boundary.
  """

  @version "0.1.0"

  @doc "The SDK contract version used for package compatibility checks."
  def version, do: @version
end
