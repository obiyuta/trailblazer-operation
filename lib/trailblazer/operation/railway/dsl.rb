module Trailblazer
  module Operation::Railway
    # WARNING: The API here is still in a state of flux since we want to provide a simple yet flexible solution.
    # This is code executed at compile-time and can be slow.
    # @note `__sequence__` is a private concept, your custom DSL code should not rely on it.


    # DRAFT
    #  direction: "(output) signal"

    # document ## Outputs
    #   task/acti has outputs, role_to_target says which task output goes to what next task in the composing acti.

    module DSL
      def pass(proc, options={}); add_step!(:pass, proc, options, default_task_outputs: default_task_outputs(options) ); end
      def fail(proc, options={}); add_step!(:fail, proc, options, default_task_outputs: default_task_outputs(options) ); end
      def step(proc, options={}); add_step!(:step, proc, options, default_task_outputs: default_task_outputs(options) ); end
      alias_method :success, :pass
      alias_method :failure, :fail

      private

      def role_to_target_for_pass(task, options)
        {
          :success => "End.success",
          :failure => "End.success"
        }
      end

      def role_to_target_for_fail(task, options)
        {
          :success => "End.failure",
          :failure => "End.failure"
        }
      end

      def role_to_target_for_step(task, options)
        {
          :success => "End.success",
          :failure => "End.failure"
        }
      end

      def insert_before_for_pass(task, options)
        "End.success"
      end

      def insert_before_for_fail(task, options)
        "End.failure"
      end

      def insert_before_for_step(task, options)
        "End.success"
      end

      # An unaware step task usually has two outputs, one end event for success and one for failure.
      # Note that macros have to define their outputs when inserted and don't need a default config.
      def default_task_outputs(options)
        { Circuit::Right => { role: :success }, Circuit::Left => { role: :failure }}
      end

      # insert_before: "End.success",
      # outputs:       { Circuit::Right => { role: :success }, Circuit::Left => { role: :failure } }, # any outputs and their polarization, generic.
      # mappings:      { success: "End.success", failure: "End.myend" } # where do my task's outputs go?
      # always adds task on a track edge.
      # @return ElementWiring
      def wirings(task: nil, insert_before:raise, outputs:{}, connect_to:{}, node_data:raise)
        raise "missing node_data: { id: .. }" if node_data[:id].nil?

        wirings = []

        wirings << [:insert_before!, insert_before, incoming: ->(edge) { edge[:type] == :railway }, node: [ task, node_data ] ]

        # FIXME: don't mark pass_fast with :railway
        puts "@@@@@x #{task} #{outputs.inspect}"
        raise "bla no outputs remove me at some point " unless outputs.any?
        wirings += Wirings.task_outputs_to(outputs, connect_to, node_data[:id], type: :railway) # connect! for task outputs

        ElementWiring.new(wirings, node_data) # embraces all alterations for one "step".
      end

      def element(*)

      end

      # |-- compile initial act from alterations
      # |-- add step alterations
      def add_step!(type, proc, user_options, task_builder:TaskBuilder, default_task_outputs:raise)
        heritage.record(type, proc, user_options)

        # build the task.
        #   runner_options #=>{:alteration=>#<Proc:0x00000001dcbb20@test/task_wrap_test.rb:15 (lambda)>}
        task_o = #, options_from_macro, runner_options, task_outputs =
          if proc.is_a?(::Hash)
            proc
          else
            task = task_builder.(proc, Circuit::Right, Circuit::Left)


            {
              task:      task,
              outputs:   default_task_outputs,
              node_data: { id: proc }
            }
          end

        node_data = task_o[:node_data]

        node_data = normalize_node_options(node_data, user_options, proc)

        # normalize task_med
        task  = task_o[:task]
        id    = node_data[:id] || raise("this raise shouldn't be here but anyway we somehow messed up the element's id~!!!!!!")
        node_data = node_data.merge(created_by: type) # this is where we can add meta-data like "is a subprocess", "boundary events", etc.

        task_o[:node_data] = node_data # FIXME.

        role_to_target = send("role_to_target_for_#{type}",  task, user_options) #=> { :success => [ "End.success" ] }
        insert_before  = send("insert_before_for_#{type}", task, user_options) #=> "End.success"

        wirings_options = {
          insert_before: insert_before, connect_to: role_to_target
        }

        wirings = wirings( wirings_options.merge(task_o) ) # TODO: this means macro could say where to insert?

# pp wirings








        self["__activity__"] = recompile_activity_for_wirings!(wirings, id, user_options) # options is :before,:after etc for Seq.insert!

        {
          activity:  self["__activity__"],

          # also return all computed data for this step:
          options:        user_options,
        }.merge(task_o)
      end

      ElementWiring = Struct.new(:instructions, :data)

      def normalize_node_options(node_data, user_options, proc)
        id = user_options[:id] || user_options[:name] || node_data[:id]

        node_data.merge( id: id ) # TODO: remove :name
      end

      # Normalizes :override and :name options.
      def normalize_sequence_options(id, override:nil, **options)
        # options = macro_options.merge(user_options)
        options = options.merge( replace: id ) if override # :override
        options
      end

      # @private
      def recompile_activity_for_wirings!(wirings, id, user_options)
        seq_options = normalize_sequence_options(id, user_options)

        sequence = self["__sequence__"]

        # Insert {Step} into {Sequence} while respecting :append, :replace, before, etc.
        sequence.insert!(wirings, seq_options) # The sequence is now an up-to-date representation of our operation's steps.

        # This op's graph are the initial wirings (different ends, etc) + the steps we added.
        activity = recompile_activity( self["__wirings__"] + sequence.to_a )
      end

      # @private
      # 1. Processes the step API's options (such as `:override` of `:before`).
      # 2. Uses `Sequence.alter!` to maintain a linear array representation of the circuit's tasks.
      #    This is then transformed into a circuit/Activity. (We could save this step with some graph magic)
      # 3. Returns a new Activity instance.
      #
      # This is called per "step"/task insertion.
      def recompile_activity(wirings)
        Trailblazer::Activity.from_wirings(wirings)
      end

      private

      # @private
      class Wirings # TODO: move to acti.
      #- connect! statements for outputs.
      # @param known_targets Hash {  }
        def self.task_outputs_to(task_outputs, known_targets, id, edge_options)
          # task_outputs is what the task has
          # known_targets are ends this activity/operation provides.
          task_outputs.collect do |signal, role:raise|
            target = known_targets[ role ]
            # TODO: add more options to edge like role: :success or role: pass_fast.

            [:connect!, source: id, edge: [signal, edge_options], target: target ] # e.g. "Left --> End.failure"
          end
        end
      end # Wiring
    end # DSL
  end
end
