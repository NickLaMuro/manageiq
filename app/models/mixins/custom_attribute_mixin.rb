module CustomAttributeMixin
  extend ActiveSupport::Concern

  CUSTOM_ATTRIBUTES_PREFIX = "virtual_custom_attribute_".freeze
  SECTION_SEPARATOR        = ":SECTION:".freeze
  DEFAULT_SECTION_NAME     = 'Custom Attribute'.freeze

  included do
    has_many   :custom_attributes,     :as => :resource, :dependent => :destroy
    has_many   :miq_custom_attributes, -> { where(:source => 'EVM') }, :as => :resource, :dependent => :destroy, :class_name => "CustomAttribute"

    # This is a set of helper getter and setter methods to support the transition
    # between "custom_*" fields in the model and using the custom_attributes table.
    (1..9).each do |custom_id|
      custom_str = "custom_#{custom_id}"
      getter     = custom_str.to_sym
      setter     = "#{custom_str}=".to_sym

      define_method(getter) do
        miq_custom_get(custom_str)
      end
      virtual_column getter, :type => :string  # uses not set since miq_custom_get re-queries

      define_method(setter) do |value|
        miq_custom_set(custom_str, value)
      end
    end

    def self.custom_keys
      custom_attr_scope = CustomAttribute.where(:resource_type => base_class.name).where.not(:name => nil).distinct.pluck(:name, :section)
      custom_attr_scope.map do |x|
        "#{x[0]}#{x[1] ? SECTION_SEPARATOR + x[1] : ''}"
      end
    end

    def self.load_custom_attributes_for(cols)
      custom_attributes = CustomAttributeMixin.select_virtual_custom_attributes(cols)
      custom_attributes.each { |custom_attribute| add_custom_attribute(custom_attribute) }
    end

    def self.add_custom_attribute(custom_attribute)
      return if respond_to?(custom_attribute)

      ca_method_name       = custom_attribute.to_sym
      ca_where_method_name = "#{custom_attribute}_where_args".to_sym
      _without_prefix      = custom_attribute.sub(CUSTOM_ATTRIBUTES_PREFIX, "")
      ca_sql_col_name      = _without_prefix.tr("-.:", "_").downcase
      ca_name, ca_section  = _without_prefix.split(SECTION_SEPARATOR).map do |col_val|
                               Arel::Nodes::SqlLiteral.new("'#{col_val}'")
                             end

      virtual_attr_arel = lambda do |t|
        ca_table      = CustomAttribute.arel_table
        resource_name = Arel::Nodes::SqlLiteral.new("'#{self.name}'")

        ca_resource_filter = ca_table[:resource_id].eq(t[:id]).and(
                               ca_table[:resource_type].eq(resource_name)
                             )

        ca_table.project(ca_table[:value])
                .where(send(ca_where_method_name).and(ca_resource_filter))
                .as(ca_sql_col_name)
      end

      virtual_attribute(ca_method_name,
                        :string,
                        :uses => :custom_attributes,
                        :arel => virtual_attr_arel
                       )

      define_singleton_method(ca_where_method_name) do
        ca_table = CustomAttribute.arel_table
        where_clause = ca_table[:name].eq(ca_name)
        where_clause = where_clause.and(ca_table[:section].eq(ca_section))
        where_clause
      end
      private_class_method ca_where_method_name

      define_method(ca_method_name) do
        if has_attribute?(ca_sql_col_name)
          self[ca_sql_col_name]
        else
          custom_attributes.find_by(self.class.send(ca_where_method_name))
                           .try(:value)
        end
      end
    end
  end

  def self.to_human(column)
    col_name, section = column.gsub(CustomAttributeMixin::CUSTOM_ATTRIBUTES_PREFIX, '').split(SECTION_SEPARATOR)
    _("%{section}: %{custom_key}") % { :custom_key => col_name, :section => section.try(:titleize) || DEFAULT_SECTION_NAME}
  end

  def self.column_name(custom_key)
    return if custom_key.nil?
    CustomAttributeMixin::CUSTOM_ATTRIBUTES_PREFIX + custom_key
  end

  def self.select_virtual_custom_attributes(cols)
    cols.nil? ? [] : cols.select { |x| x.start_with?(CUSTOM_ATTRIBUTES_PREFIX) }
  end

  def miq_custom_keys
    miq_custom_attributes.pluck(:name)
  end

  def miq_custom_get(key)
    miq_custom_attributes.find_by(:name => key.to_s).try(:value)
  end

  def miq_custom_set(key, value)
    return miq_custom_delete(key) if value.blank?

    record = miq_custom_attributes.find_by(:name => key.to_s)
    if record.nil?
      miq_custom_attributes.create(:name => key.to_s, :value => value)
    else
      record.update_attributes(:value => value)
    end
  end

  def miq_custom_delete(key)
    miq_custom_attributes.find_by(:name => key.to_s).try(:delete)
  end
end
