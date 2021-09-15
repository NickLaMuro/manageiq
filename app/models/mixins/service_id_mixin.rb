module ServiceIdMixin
  extend ActiveSupport::Concern

  included do
    virtual_attribute :service_id, :integer, :uses => :service, :arel => (lambda do |t|
      table = Service.arel_table

      __service_arel(table.project(table[:id]))
    end)

    virtual_attribute :service_guid, :string, :uses => :service, :arel => (lambda do |t|
      table = Service.arel_table

      __service_arel(table.project(table[:guid]))
    end)
  end

  module ClassMethods
    def __service_resource_type
      @__service_resource_type ||= Arel::Nodes::SqlLiteral.new("'VmOrTemplate'") # TODO:  Undo hardcode
    end

    def __service_resources_tbl
      @__service_resources_tbl ||= ServiceResource.arel_table
    end

    def __service_arel(arel)
      table = arel.source.left # Does this work all the time?

      arel.join(__service_resources_tbl).on(table[:id].eq(__service_resources_tbl[:service_id]))
          .where(arel_table[:id].eq(__service_resources_tbl[:resource_id])
            .and(__service_resources_tbl[:resource_type].eq(__service_resource_type)))

    end
  end
end
