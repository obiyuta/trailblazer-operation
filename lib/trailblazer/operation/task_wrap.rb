module Trailblazer
  module Operation::Railway
    module TaskWrap
      def self.included(includer)
        includer.extend ClassMethods # ::call, ::inititalize_pipetree!
        includer.extend DSL

        includer.initialize_task_wraps!
      end

      module ClassMethods
        def initialize_task_wraps!
          heritage.record :initialize_task_wraps!

          self["__task_wraps__"] = {}
        end

        # options is a Skill already.
        def __call__(direction, options, flow_options={}) # FIXME: direction
          activity     = self["__activity__"]

          # TODO: we can probably save a lot of time here by using constants.
          wrap_static  = Circuit::Wrap::Alterations.new( map: self["__task_wraps__"] )
          wrap_runtime = Circuit::Wrap::Alterations.new

          # override:
          flow_options = flow_options.merge(
            runner:      Circuit::Wrap::Runner,
            wrap_static: wrap_static,
            debug:       activity.circuit.instance_variable_get(:@name)
          )
          # reverse_merge:
          flow_options = { wrap_runtime: wrap_runtime }.merge(flow_options)

          super(activity[:Start], options, flow_options) # Railway::__call__
        end
      end

      module DSL
        def build_task_for(*args)
          super.tap do |task, options, alteration: nil, **| # Railway::DSL::build_task_for
            task_wrap = Circuit::Wrap::Activity # default.
            task_wrap = alteration.(task_wrap) if alteration # macro might want to apply changes to the static task_wrap (e.g. Inject)

            self["__task_wraps__"][task] = [ Proc.new{task_wrap} ]
          end
        end
      end
    end # TaskWrap
  end
end