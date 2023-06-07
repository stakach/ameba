require "./base_visitor"

module Ameba::AST
  # AST Visitor that traverses the source and constructs scopes.
  class ScopeVisitor < BaseVisitor
    # Non-exhaustive list of nodes to be visited by Ameba's rules.
    NODES = {
      ClassDef,
      ModuleDef,
      EnumDef,
      LibDef,
      FunDef,
      TypeDef,
      TypeOf,
      CStructOrUnionDef,
      ProcLiteral,
      Block,
      Macro,
      MacroFor,
    }

    SPECIAL_NODE_NAMES = %w[super previous_def]
    RECORD_NODE_NAME   = "record"

    @scope_queue = [] of Scope
    @current_scope : Scope
    @current_assign : Crystal::ASTNode?
    @visibility_modifier : Crystal::Visibility?
    @skip : Array(Crystal::ASTNode.class)?

    def initialize(@rule, @source, skip = nil)
      @skip = skip.try &.map(&.as(Crystal::ASTNode.class))
      @current_scope = Scope.new(@source.ast) # top level scope
      @source.ast.accept self
      @scope_queue.each { |scope| @rule.test @source, scope.node, scope }
    end

    private def on_scope_enter(node)
      return if skip?(node)

      scope = Scope.new(node, @current_scope)
      scope.visibility = @visibility_modifier

      @current_scope = scope
    end

    private def on_scope_end(node)
      @scope_queue << @current_scope

      @visibility_modifier = nil

      # go up if this is not a top level scope
      return unless outer_scope = @current_scope.outer_scope
      @current_scope = outer_scope
    end

    private def on_assign_end(target, node)
      target.is_a?(Crystal::Var) &&
        @current_scope.assign_variable(target.name, node)
    end

    # :nodoc:
    def end_visit(node : Crystal::ASTNode)
      on_scope_end(node) if @current_scope.eql?(node)
    end

    {% for name in NODES %}
      # :nodoc:
      def visit(node : Crystal::{{ name }})
        on_scope_enter(node)
      end
    {% end %}

    # :nodoc:
    def visit(node : Crystal::VisibilityModifier)
      @visibility_modifier = node.modifier
      true
    end

    # :nodoc:
    def visit(node : Crystal::Yield)
      @current_scope.yields = true
    end

    # :nodoc:
    def visit(node : Crystal::Def)
      node.name == "->" || on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::Assign | Crystal::OpAssign | Crystal::MultiAssign | Crystal::UninitializedVar)
      @current_assign = node
    end

    # :nodoc:
    def end_visit(node : Crystal::Assign | Crystal::OpAssign)
      on_assign_end(node.target, node)
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def end_visit(node : Crystal::MultiAssign)
      node.targets.each { |target| on_assign_end(target, node) }
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def end_visit(node : Crystal::UninitializedVar)
      on_assign_end(node.var, node)
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def visit(node : Crystal::TypeDeclaration)
      return unless (var = node.var).is_a?(Crystal::Var)

      @current_scope.add_variable(var)
      @current_scope.add_type_dec_variable(node)
      @current_assign = node.value unless node.value.nil?
    end

    def end_visit(node : Crystal::TypeDeclaration)
      return unless (var = node.var).is_a?(Crystal::Var)

      on_assign_end(var, node)
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def visit(node : Crystal::Arg)
      @current_scope.add_argument(node)
    end

    # :nodoc:
    def visit(node : Crystal::InstanceVar)
      @current_scope.add_ivariable(node)
    end

    # :nodoc:
    def visit(node : Crystal::Var)
      variable = @current_scope.find_variable node.name

      case
      when @current_scope.arg?(node) # node is an argument
        @current_scope.add_argument(node)
      when variable.nil? && @current_assign # node is a variable
        @current_scope.add_variable(node)
      when variable # node is a reference
        reference = variable.reference node, @current_scope
        if @current_assign.is_a?(Crystal::OpAssign) || !reference.target_of?(@current_assign)
          variable.reference_assignments!
        end
      end
    end

    # :nodoc:
    def visit(node : Crystal::Call)
      case
      when @current_scope.def?
        if node.name.in?(SPECIAL_NODE_NAMES) && node.args.empty?
          @current_scope.arguments.each do |arg|
            variable = arg.variable
            variable.reference(variable.node, @current_scope).explicit = false
          end
        end
        true
      when @current_scope.top_level? && record_macro?(node)
        false
      else
        true
      end
    end

    private def record_macro?(node)
      node.name == RECORD_NODE_NAME && node.args.first?.is_a?(Crystal::Path)
    end

    private def skip?(node)
      !!@skip.try(&.includes?(node.class))
    end
  end
end
