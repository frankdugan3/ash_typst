defmodule AshTypst.Test.Read.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshTypst.Test.Read.Item do
  @moduledoc """
  A resource whose render actions exercise the `read` entity.

  Defined under `test/support` so it compiles with the application, ensuring the
  derived protocol implementation is picked up by protocol consolidation.
  """
  use Ash.Resource,
    domain: AshTypst.Test.Read.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypst.Resource]

  require Ash.Query

  @derive AshTypst.Code

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :serial_no, :string, public?: true, allow_nil?: false
    attribute :packing_slip_no, :string, public?: true
    attribute :location, :string, public?: true
    attribute :status, :atom, public?: true, default: :packed
    attribute :owner_id, :uuid, public?: true
    attribute :shipped_at, :utc_datetime, public?: true
  end

  calculations do
    calculate :label, :string, expr(^arg(:prefix) <> serial_no) do
      public? true
      argument :prefix, :string, allow_nil?: false
    end
  end

  actions do
    defaults [
      :read,
      create: [:serial_no, :packing_slip_no, :location, :status, :owner_id, :shipped_at]
    ]

    read :keyset do
      pagination keyset?: true, default_limit: 2
    end

    read :keyset_no_default do
      pagination keyset?: true
    end

    read :unpaginated

    read :offset do
      pagination offset?: true, default_limit: 2
    end

    read :at_location do
      pagination keyset?: true, required?: false
      argument :location, :string, allow_nil?: false
      filter expr(location == ^arg(:location))
    end

    read :from_context do
      pagination keyset?: true, required?: false

      prepare fn query, _context ->
        Ash.Query.filter(query, location == ^query.context[:location])
      end
    end

    action :not_a_read, :string do
      run fn _input, _context -> {:ok, "nope"} end
    end
  end

  typst do
    template :records do
      markup ~TYPST"""
      #import "data.typ": records
      [#records.map(r => r.serial_no).join(",")]
      """
    end

    template :labels do
      markup ~TYPST"""
      #import "data.typ": records
      [#records.map(r => r.label).join(",")]
      """
    end

    template :record do
      markup ~TYPST"""
      #import "data.typ": record
      [#if record == none [none] else [#record.serial_no]]
      """
    end

    template :shipped do
      markup ~TYPST"""
      #import "data.typ": record, args
      [#record.shipped_at.hour() #args.at.hour()]
      """
    end

    template :shipped_many do
      markup ~TYPST"""
      #import "data.typ": records
      [#records.first().shipped_at.hour()]
      """
    end

    render :by_and do
      template :records
      format :html

      argument :packing_slip_no, :string, allow_nil?: false
      argument :location, :string, allow_nil?: false

      read :many do
        filter expr(packing_slip_no == ^arg(:packing_slip_no) and location == ^arg(:location))
        select [:serial_no]
        sort serial_no: :asc
      end
    end

    render :by_or do
      template :records
      format :html

      argument :packing_slip_no, :string, allow_nil?: false
      argument :location, :string, allow_nil?: false

      read :many do
        filter expr(packing_slip_no == ^arg(:packing_slip_no) or location == ^arg(:location))
        sort serial_no: :asc
      end
    end

    render :by_not do
      template :records
      format :html

      argument :location, :string, allow_nil?: false

      read :many do
        filter expr(not (location == ^arg(:location)))
        sort serial_no: :asc
      end
    end

    render :by_in do
      template :records
      format :html

      argument :statuses, {:array, :atom}, allow_nil?: false

      read :many do
        filter expr(status in ^arg(:statuses))
        sort serial_no: :asc
      end
    end

    render :by_list_of_args do
      template :records
      format :html

      argument :first, :string, allow_nil?: false
      argument :second, :string, allow_nil?: false

      read :many do
        filter expr(serial_no in [^arg(:first), ^arg(:second)])
        sort serial_no: :asc
      end
    end

    render :by_nested_call do
      template :records
      format :html

      argument :serial_no, :string, allow_nil?: false
      argument :location, :string, allow_nil?: false

      read :many do
        filter expr(
                 string_downcase(serial_no) == string_downcase(^arg(:serial_no)) and
                   location == ^arg(:location)
               )
      end
    end

    render :by_keyword do
      template :records
      format :html

      argument :location, :string, allow_nil?: false

      read :many do
        filter location: arg(:location)
        sort serial_no: :asc
      end
    end

    render :by_nilable do
      template :records
      format :html

      argument :location, :string

      read :many do
        filter expr(location == ^arg(:location))
        sort serial_no: :asc
      end
    end

    render :by_actor do
      template :records
      format :html

      read :many do
        filter expr(owner_id == ^actor(:id))
        sort serial_no: :asc
      end
    end

    render :by_tenant do
      template :records
      format :html

      read :many do
        filter expr(location == ^tenant())
        sort serial_no: :asc
      end
    end

    render :by_context do
      template :records
      format :html

      read :many do
        filter expr(location == ^context(:location))
        sort serial_no: :asc
      end
    end

    render :one_by_and do
      template :record
      format :html

      argument :packing_slip_no, :string, allow_nil?: false
      argument :serial_no, :string, allow_nil?: false

      read :one do
        filter expr(packing_slip_no == ^arg(:packing_slip_no) and serial_no == ^arg(:serial_no))
      end
    end

    render :one_or_none do
      template :record
      format :html

      argument :serial_no, :string, allow_nil?: false

      read :one do
        filter expr(serial_no == ^arg(:serial_no))
        not_found nil
      end
    end

    render :one_explicit_error do
      template :record
      format :html

      argument :serial_no, :string, allow_nil?: false

      read :one do
        filter expr(serial_no == ^arg(:serial_no))
        not_found :error
      end
    end

    render :one_keyset do
      template :record
      format :html

      argument :serial_no, :string, allow_nil?: false

      read :one do
        action :keyset
        filter expr(serial_no == ^arg(:serial_no))
      end
    end

    render :load_with_arg do
      template :labels
      format :html

      argument :prefix, :string, allow_nil?: false

      read :many do
        load label: %{prefix: arg(:prefix)}
        sort serial_no: :asc
      end
    end

    render :sort_with_arg do
      template :records
      format :html

      argument :prefix, :string, allow_nil?: false

      read :many do
        sort label: {%{prefix: arg(:prefix)}, :desc}
      end
    end

    render :all do
      template :records
      format :html

      read :many do
        sort serial_no: :asc
        batch_size 2
      end
    end

    render :all_keyset do
      template :records
      format :html

      read :many do
        action :keyset
        sort serial_no: :asc
        batch_size 2
      end
    end

    render :all_keyset_no_default do
      template :records
      format :html

      read :many do
        action :keyset_no_default
        sort serial_no: :asc
      end
    end

    render :all_offset do
      template :records
      format :html

      read :many do
        action :offset
        sort serial_no: :asc
      end
    end

    render :limited_keyset do
      template :records
      format :html

      read :many do
        action :keyset
        sort serial_no: :asc
        limit 3
      end
    end

    render :unstreamed do
      template :records
      format :html

      read :many do
        action :unpaginated
        sort serial_no: :asc

        stream_with :none
      end
    end

    render :unstreamed_filtered do
      template :records
      format :html

      argument :serial_no, :string, allow_nil?: false

      read :many do
        filter expr(serial_no == ^arg(:serial_no))
        stream_with :none
      end
    end

    render :unstreamed_paginated do
      template :records
      format :html

      read :many do
        sort serial_no: :asc

        stream_with :none
      end
    end

    render :forced_offset do
      template :records
      format :html

      read :many do
        sort serial_no: :asc
        batch_size 2
        stream_with :offset
      end
    end

    render :with_action_argument do
      template :records
      format :html

      argument :where, :string, allow_nil?: false

      read :many do
        action :at_location
        arguments location: arg(:where)
        sort serial_no: :asc
      end
    end

    render :with_preparation_context do
      template :records
      format :html

      argument :where, :string, allow_nil?: false

      prepare fn input, _context ->
        Ash.ActionInput.set_context(input, %{location: input.arguments.where})
      end

      read :many do
        action :from_context
        sort serial_no: :asc
      end
    end

    render :shipped do
      template :shipped
      format :html
      encoding_context %{timezone: arg(:timezone)}

      argument :serial_no, :string, allow_nil?: false
      argument :at, :utc_datetime, allow_nil?: false
      argument :timezone, :string

      read :one do
        filter expr(serial_no == ^arg(:serial_no))
      end
    end

    render :shipped_many do
      template :shipped_many
      format :html
      encoding_context %{timezone: "Asia/Tokyo"}

      read :many do
        sort serial_no: :asc
      end
    end
  end
end

defmodule AshTypst.Test.Read.Secured do
  @moduledoc """
  A resource whose read policy requires an actor, to observe whether the
  caller's actor and `authorize?` reach the inner read of a render action.
  """
  use Ash.Resource,
    domain: AshTypst.Test.Read.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypst.Resource]

  @derive AshTypst.Code

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :serial_no, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, create: [:serial_no]]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:action, :create]) do
      authorize_if always()
    end
  end

  typst do
    template :records do
      markup ~TYPST"""
      #import "data.typ": records
      [#records.map(r => r.serial_no).join(",")]
      """
    end

    template :record do
      markup ~TYPST"""
      #import "data.typ": record
      [#record.serial_no]
      """
    end

    render :render_all_unstreamed do
      template :records
      format :html

      read :many do
        sort serial_no: :asc
        stream_with :none
      end
    end

    render :render_all do
      template :records
      format :html

      read :many do
        sort serial_no: :asc
      end
    end

    render :render_first do
      template :record
      format :html

      read :one do
      end
    end
  end
end
