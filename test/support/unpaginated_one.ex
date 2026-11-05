defmodule AshTypst.Test.UnpaginatedOne do
  @moduledoc """
  A resource whose `read :one` render uses a read action without pagination.

  Defined under `test/support` so it compiles with the application, ensuring the
  derived protocol implementation is picked up by protocol consolidation.
  """
  use Ash.Resource,
    domain: AshTypst.Test.CodeDerive.Domain,
    extensions: [AshTypst.Resource]

  @derive AshTypst.Code

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
    read :unpaginated
  end

  typst do
    template :doc do
      markup "= Test"
    end

    render :render_doc do
      template :doc
      format :pdf

      read :one do
        action :unpaginated
      end
    end
  end
end
