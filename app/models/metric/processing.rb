module Metric::Processing
  TYPE_AVAILABLE = "available".freeze
  TYPE_ALLOCATED = "allocated".freeze
  TYPE_USED      = "used".freeze
  TYPE_RATE      = "rate".freeze
  TYPE_RESERVED  = "reserved".freeze
  TYPE_COUNT     = "count".freeze
  TYPE_NUMVCPUS  = "numvcpus".freeze
  TYPE_SOCKETS   = "sockets".freeze

  DERIVED_COLS = {
    :derived_cpu_available             => [nil, "cpu", TYPE_AVAILABLE],
    :derived_cpu_reserved              => [:reserve_cpu, "cpu", TYPE_RESERVED],
    :derived_host_count_off            => [:host_count_off, "host", TYPE_COUNT],
    :derived_host_count_on             => [:host_count_on, "host", TYPE_COUNT],
    :derived_host_count_total          => [:host_count_total, "host", TYPE_COUNT],
    :derived_memory_available          => [nil, "memory", TYPE_AVAILABLE],
    :derived_memory_reserved           => [:reserve_mem, "memory", TYPE_RESERVED],
    :derived_memory_used               => [nil, "memory", TYPE_USED],
    :derived_host_sockets              => [nil, "host", TYPE_SOCKETS],
    :derived_vm_allocated_disk_storage => [:vm_allocated_disk_storage, "vm", TYPE_ALLOCATED],
    :derived_vm_count_off              => [:vm_count_off, "vm", TYPE_COUNT],
    :derived_vm_count_on               => [:vm_count_on, "vm", TYPE_COUNT],
    :derived_vm_count_total            => [:vm_count_total, "vm", TYPE_COUNT],
    # TODO: This is cpu_total_cores and needs to be renamed, but reports depend on the name :numvcpus
    :derived_vm_numvcpus               => [nil, "vm", TYPE_NUMVCPUS],
    # See also #TODO on VimPerformanceState.capture
    :derived_vm_used_disk_storage      => [:vm_used_disk_storage, "vm", TYPE_USED],
    # TODO(lsmola) as described below, this field should be named derived_cpu_used
    # FIXME(nicklamuro) FYI: This doesn't really follow the convention of those
    # above it (see above), so I just tried to follow the pattern the others
    # have of [method, group, type]
    :cpu_usagemhz_rate_average         => [nil, "cpu", TYPE_RATE]
  }.freeze

  VALID_PROCESS_TARGETS = [
    VmOrTemplate,
    Container,
    ContainerGroup,
    ContainerNode,
    ContainerProject,
    ContainerReplicator,
    ContainerService,
    Host,
    AvailabilityZone,
    HostAggregate,
    EmsCluster,
    ExtManagementSystem,
    MiqRegion,
    MiqEnterprise,
    Service
  ]

  def self.process_derived_columns(obj, attrs, ts = nil)
    unless VALID_PROCESS_TARGETS.any? { |t| obj.kind_of?(t) }
      raise _("object %{name} is not one of %{items}") % {:name  => obj,
                                                          :items => VALID_PROCESS_TARGETS.collect(&:name).join(", ")}
    end

    ts = attrs[:timestamp] if ts.nil?
    state = obj.vim_performance_state_for_ts(ts)
    total_cpu = state.total_cpu || 0
    total_mem = state.total_mem || 0
    result = {}

    have_cpu_metrics = attrs[:cpu_usage_rate_average] || attrs[:cpu_usagemhz_rate_average]
    have_mem_metrics = attrs[:mem_usage_absolute_average] || attrs[:derived_memory_used]

    DERIVED_COLS.each do |col, val|
      method, group, typ = val
      next if group == "vm" && obj.kind_of?(Service) && typ != "count"
      case typ
      when TYPE_AVAILABLE
        # Do not derive "available" values if there haven't been any usage
        # values collected
        if group == "cpu"
          result[col] = total_cpu if have_cpu_metrics && total_cpu > 0
        else
          result[col] = total_mem if have_mem_metrics && total_mem > 0
        end
      when TYPE_ALLOCATED
        result[col] = state.send(method) if state.respond_to?(method)
      when TYPE_USED
        if group == "cpu"
          # TODO: This branch is never called because there isn't a column
          # called derived_cpu_used.  The callers, such as chargeback, generally
          # use cpu_usagemhz_rate_average directly, and the column may not be
          # needed, but perhaps should be added to normalize like is done for
          # memory.  The derivation here could then use cpu_usagemhz_rate_average
          # directly if avaiable, otherwise do the calculation below.
          result[col] = (attrs[:cpu_usage_rate_average] / 100 * total_cpu) unless total_cpu == 0 || attrs[:cpu_usage_rate_average].nil?
        elsif group == "memory"
          if attrs[:mem_usage_absolute_average].nil?
            # If we can't get percentage usage, just used RAM in MB, lets compute percentage usage
            attrs[:mem_usage_absolute_average] = 100.0 / total_mem * attrs[:derived_memory_used] if total_mem > 0 && !attrs[:derived_memory_used].nil?
          else
            # We have percentage usage of RAM, lets compute consumed RAM in MB
            result[col] = (attrs[:mem_usage_absolute_average] / 100 * total_mem) unless total_mem == 0 || attrs[:mem_usage_absolute_average].nil?
          end
        else
          result[col] = state.send(method) if state.respond_to?(method)
        end
      when TYPE_RATE
        if col.to_s == "cpu_usagemhz_rate_average" && attrs[:cpu_usagemhz_rate_average].blank?
          # TODO(lsmola) for some reason, this column is used in chart, although from processing code above, it should
          # be named derived_cpu_used. Investigate what is the right solution and make it right. For now lets fill
          # the column shown in charts.
          result[col] = (attrs[:cpu_usage_rate_average] / 100 * total_cpu) unless total_cpu == 0 || attrs[:cpu_usage_rate_average].nil?
        end
      when TYPE_RESERVED
        result[col] = state.send(method)
      when TYPE_COUNT
        result[col] = state.send(method)
      when TYPE_NUMVCPUS # This is actually logical cpus.  See note above.
        # Do not derive "available" values if there haven't been any usage
        # values collected
        result[col] = state.numvcpus if have_cpu_metrics && state.try(:numvcpus).to_i > 0
      when TYPE_SOCKETS
        result[col] = state.host_sockets
      end
    end

    result[:assoc_ids] = state.assoc_ids
    result[:tag_names] = state.tag_names
    result[:parent_host_id] = state.parent_host_id
    result[:parent_storage_id] = state.parent_storage_id
    result[:parent_ems_id] = state.parent_ems_id
    result[:parent_ems_cluster_id] = state.parent_ems_cluster_id
    result
  end

  def self.add_missing_intervals(obj, interval_name, start_time, end_time)
    klass, meth = Metric::Helper.class_and_association_for_interval_name(interval_name)

    scope = obj.send(meth).for_time_range(start_time, end_time)
    scope = scope.where(:capture_interval_name => interval_name) if interval_name != "realtime"
    extrapolate(klass, scope)
  end

  def self.extrapolate(klass, scope)
    last_perf = {}
    scope.order("timestamp, capture_interval_name").each do |perf|
      interval = interval_name_to_interval(perf.capture_interval_name)
      last_perf[interval] = perf if last_perf[interval].nil?

      if (perf.timestamp - last_perf[interval].timestamp) <= interval
        last_perf[interval] = perf
        next
      end

      new_perf = create_new_metric(klass, last_perf[interval], perf, interval)
      new_perf.save!

      last_perf[interval] = perf
    end
  end

  def self.create_new_metric(klass, last_perf, perf, interval)
    attrs = last_perf.attributes
    attrs.delete('id')
    attrs['timestamp'] += interval
    attrs['capture_interval'] = 0
    new_perf = klass.new(attrs)
    Metric::Rollup::ROLLUP_COLS.each do |c|
      next if new_perf.send(c).nil? || perf.send(c).nil?
      new_perf.send(c.to_s + "=", (new_perf.send(c) + perf.send(c)) / 2)
    end

    unless perf.assoc_ids.nil?
      Metric::Rollup::ASSOC_KEYS.each do |assoc|
        next if new_perf.assoc_ids.nil? || new_perf.assoc_ids[assoc].blank? || perf.assoc_ids[assoc].blank?
        new_perf.assoc_ids[assoc][:on] ||= []
        new_perf.assoc_ids[assoc][:off] ||= []
        new_perf.assoc_ids[assoc][:on]  = (new_perf.assoc_ids[assoc][:on] + perf.assoc_ids[assoc][:on]).uniq!
        new_perf.assoc_ids[assoc][:off] = (new_perf.assoc_ids[assoc][:off] + perf.assoc_ids[assoc][:off]).uniq!
      end
    end
    new_perf
  end
  private_class_method :extrapolate, :create_new_metric

  def self.interval_name_to_interval(name)
    case name
    when "realtime" then 20
    when "hourly" then   1.hour.to_i
    when "daily" then    1.day.to_i
    else raise _("unknown interval name: [%{name}]") % {:name => name}
    end
  end
end
