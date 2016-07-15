module ROM
  class Repository
    class RelationProxy
      # Provides convenient methods for producing combined relations
      #
      # @api public
      module Combine
        # Return combine representation of a loading-proxy relation
        #
        # This will carry meta info used to produce a correct AST from a relation
        # so that correct mapper can be generated
        #
        # @return [RelationProxy]
        #
        # @api private
        def combined(name, keys, type)
          meta = { keys: keys, combine_type: type, combine_name: name }
          with(name: name, meta: meta)
        end

        # Combine with other relations
        #
        # @example
        #   # combining many
        #   users.combine(many: { tasks: [tasks, id: :task_id] })
        #   users.combine(many: { tasks: [tasks.for_users, id: :task_id] })
        #
        #   # combining one
        #   users.combine(one: { task: [tasks, id: :task_id] })
        #
        # @param [Hash] options
        #
        # @return [RelationProxy]
        #
        # @api public
        def combine(*args)
          options = args[0].is_a?(Hash) ? args[0] : args

          combine_opts = Hash.new { |h, k| h[k] = {} }

          options.each do |(type, relations)|
            if relations
              combine_opts[type] = combine_opts_from_relations(relations)
            else
              result, curried, keys = combine_opts_for_assoc(type)
              combine_opts[result][type] = [curried, keys]
            end
          end

          nodes = combine_opts.flat_map do |type, relations|
            relations.map { |name, (relation, keys)|
              relation.combined(name, keys, type)
            }
          end

          __new__(relation.combine(*nodes))
        end

        # Shortcut for combining with parents which infers the join keys
        #
        # @example
        #   tasks.combine_parents(one: users)
        #
        # @param [Hash] options
        #
        # @return [RelationProxy]
        #
        # @api public
        def combine_parents(options)
          combine_opts = {}

          options.each do |type, parents|
            combine_opts[type] =
              case parents
              when Hash
                parents.each_with_object({}) { |(name, parent), r|
                  keys = combine_keys(parent, relation, :parent)
                  r[name] = [parent, keys]
                }
              when Array
                parents.each_with_object({}) { |parent, r|
                  tuple_key = parent.combine_tuple_key(type)
                  keys = combine_keys(parent, relation, :parent)
                  r[tuple_key] = [parent, keys]
                }
              else
                tuple_key = parents.combine_tuple_key(type)
                keys = combine_keys(parents, relation, :parent)
                { tuple_key => [parents, keys] }
              end
          end

          combine(combine_opts)
        end

        # Shortcut for combining with children which infers the join keys
        #
        # @example
        #   users.combine_parents(many: tasks)
        #
        # @param [Hash] options
        #
        # @return [RelationProxy]
        #
        # @api public
        def combine_children(options)
          combine_opts = {}

          options.each do |type, children|
            combine_opts[type] =
              case children
              when Hash
                children.each_with_object({}) { |(name, child), r|
                  keys = combine_keys(relation, child, :children)
                  r[name] = [child, keys]
                }
              when Array
                parents.each_with_object({}) { |child, r|
                  tuple_key = parent.combine_tuple_key(type)
                  keys = combine_keys(relation, child, :children)
                  r[tuple_key] = [parent, keys]
                }
              else
                tuple_key = children.combine_tuple_key(type)
                keys = combine_keys(relation, children, :children)
                { tuple_key => [children, keys] }
              end
          end

          combine(combine_opts)
        end

        protected

        # Infer join/combine keys for a given relation and association type
        #
        # When source has association corresponding to target's name, it'll be
        # used to get the keys. Otherwise we fall back to using default keys based
        # on naming conventions.
        #
        # @param [RelationProxy] relation
        # @param [Symbol] type The type can be either :parent or :children
        #
        # @return [Hash<Symbol=>Symbol>]
        #
        # @api private
        def combine_keys(source, target, type)
          source.associations.try(target.name) { |assoc|
            assoc.combine_keys(__registry__)
          } or infer_combine_keys(source, target, type)
        end

        # Build combine options from a relation mapping hash passed to `combine`
        #
        # This method will infer combine keys either from defined associations
        # or use the keys provided explicitly for ad-hoc combines
        #
        # It returns a mapping like `name => [preloadable_relation, combine_keys]`
        # and this mapping is used by `combine` to build a full relation graph
        #
        # @api private
        def combine_opts_from_relations(relations)
          relations.each_with_object({}) do |(name, (other, keys)), h|
            h[name] =
              if other.curried?
                [other, keys]
              else
                rel = combine_from_assoc(name, other) { other.combine_method(relation, keys) }
                [rel, keys]
              end
          end
        end

        # Try to get a preloadable relation from a defined association
        #
        # If association doesn't exist we call the fallback block
        #
        # @return [RelationProxy]
        #
        # @api private
        def combine_from_assoc(name, other, &fallback)
          associations.try(name) { |assoc| other.for_combine(assoc) } or fallback.call
        end

        # Extract result (either :one or :many), preloadable relation and its keys
        # by using given association name
        #
        # This is used when a flat list of association names was passed to `combine`
        #
        # @api private
        def combine_opts_for_assoc(name)
          assoc = relation.associations[name]
          curried = registry[assoc.target.relation].for_combine(assoc)
          keys = assoc.combine_keys(__registry__)
          [assoc.result, curried, keys]
        end

        # Build a preloadable relation for relation graph
        #
        # When a given relation defines `for_other_relation` then it will be used
        # to preload `other_relation`. ie `users` relation defines `for_tasks`
        # then when we preload tasks for users, this custom method will be used
        #
        # This *defaults* to the built-in `for_combine` with explicitly provided
        # keys
        #
        # @return [RelationProxy]
        #
        # @api private
        def combine_method(other, keys)
          custom_name = :"for_#{other.name.dataset}"

          if relation.respond_to?(custom_name)
            __send__(custom_name)
          else
            for_combine(keys)
          end
        end

        # Infer key under which a combine relation will be loaded
        #
        # This is used in cases like ad-hoc combines where relation was passed
        # in without specifying the key explicitly, ie:
        #
        #    tasks.combine_parents(one: users)
        #
        #    # ^^^ this will be expanded under-the-hood to:
        #    tasks.combine(one: { user: users })
        #
        # @return [Symbol]
        #
        # @api private
        def combine_tuple_key(result)
          if result == :one
            Inflector.singularize(base_name.relation).to_sym
          else
            base_name.relation
          end
        end

        # Fallback mechanism for `combine_keys` when there's no association defined
        #
        # @api private
        def infer_combine_keys(source, target, type)
          primary_key = source.primary_key
          foreign_key = target.foreign_key(source)

          if type == :parent
            { foreign_key => primary_key }
          else
            { primary_key => foreign_key }
          end
        end
      end
    end
  end
end
