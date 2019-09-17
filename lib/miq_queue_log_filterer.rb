class MiqQueueLogFilterer
  def self.inspect_args_for(queue_msg)
    klass  = queue_msg.class_name.constantize
    method = queue_msg.method
    args   = queue_msg.args

    if klass.respond_to?("filter_args_for_#{method}")
      klass.send("filter_args_for_#{method}", args).inspect
    else
      args.inspect
    end
  end
end
