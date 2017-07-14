if defined? ActionController::Parameters
  ActionController::Parameters.class_eval do
    include MoreCoreExtensions::Shared::Nested
  end
end
