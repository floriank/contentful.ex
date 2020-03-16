defmodule Contentful.Delivery.LocalesTest do
  use ExUnit.Case

  alias Contentful.Locale
  alias Contentful.Delivery.Locales

  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  @space_id "bmehzfuz4raf"
  @access_token nil

  setup_all do
    HTTPoison.start()
  end

  setup do
    ExVCR.Config.filter_request_headers("authorization")
    :ok
  end

  describe ".fetch_all" do
    test "will fetch all locales for a given space" do
      use_cassette "locales" do
        {:ok, [%Locale{code: "en-US"}, %Locale{code: "de"}]} =
          @space_id |> Locales.fetch_all("master", @access_token)
      end
    end
  end
end