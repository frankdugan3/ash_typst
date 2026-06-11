defmodule AshTypst.Test.CodeDerive.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshTypst.Test.CodeDerive.Resource do
  @moduledoc """
  A resource that opts into the `AshTypst.Code` protocol via `@derive`.

  Defined under `test/support` so it compiles with the application, ensuring the
  derived protocol implementation is picked up by protocol consolidation.
  """
  use Ash.Resource,
    domain: AshTypst.Test.CodeDerive.Domain,
    data_layer: Ash.DataLayer.Ets

  @derive AshTypst.Code

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :secret, :string, public?: false
  end

  actions do
    defaults [:read, create: [:name, :secret]]
  end
end
