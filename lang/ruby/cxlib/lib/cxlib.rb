# frozen_string_literal: true
#
# CX Ruby binding — thin FFI wrapper around libcx.
# Locates libcx.dylib / libcx.so relative to the repo root.
#
require 'ffi'

module CXLib
  extend FFI::Library

  def self._find_lib
    lib_name = FFI::Platform.mac? ? 'libcx.dylib' : 'libcx.so'

    # 1. Explicit path override
    return ENV['LIBCX_PATH'] if ENV['LIBCX_PATH']

    candidates = []

    # 2. Directory override
    candidates << File.join(ENV['LIBCX_LIB_DIR'], lib_name) if ENV['LIBCX_LIB_DIR']

    # 3. System paths
    %w[/usr/local/lib /opt/homebrew/lib /usr/lib
       /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu].each do |dir|
      candidates << File.join(dir, lib_name)
    end

    # 4. Repo-relative fallback (development)
    repo_root = File.expand_path('../../../../../', __FILE__)
    candidates << File.join(repo_root, 'vcx', 'target', lib_name)
    candidates << File.join(repo_root, 'dist', 'lib',   lib_name)

    found = candidates.find { |p| File.exist?(p) }
    raise RuntimeError, "libcx not found. Install with 'sudo make install' or set LIBCX_PATH.\nLooked in: #{candidates.inspect}" unless found
    found
  end

  ffi_lib _find_lib

  # memory
  attach_function :cx_free,    [:pointer],          :void
  attach_function :cx_version, [],                  :pointer

  # CX input
  attach_function :cx_to_cx,          [:string, :pointer], :pointer
  attach_function :cx_to_cx_compact,  [:string, :pointer], :pointer
  attach_function :cx_ast_to_cx,      [:string, :pointer], :pointer
  attach_function :cx_to_xml,        [:string, :pointer], :pointer
  attach_function :cx_to_ast,        [:string, :pointer], :pointer
  attach_function :cx_to_json,       [:string, :pointer], :pointer
  attach_function :cx_to_yaml,       [:string, :pointer], :pointer
  attach_function :cx_to_toml,       [:string, :pointer], :pointer
  attach_function :cx_to_md,         [:string, :pointer], :pointer
  attach_function :cx_to_ast_bin,    [:string, :pointer], :pointer
  attach_function :cx_to_events_bin, [:string, :pointer], :pointer

  # XML input
  attach_function :cx_xml_to_cx,   [:string, :pointer], :pointer
  attach_function :cx_xml_to_xml,  [:string, :pointer], :pointer
  attach_function :cx_xml_to_ast,  [:string, :pointer], :pointer
  attach_function :cx_xml_to_json, [:string, :pointer], :pointer
  attach_function :cx_xml_to_yaml, [:string, :pointer], :pointer
  attach_function :cx_xml_to_toml, [:string, :pointer], :pointer
  attach_function :cx_xml_to_md,   [:string, :pointer], :pointer

  # JSON input
  attach_function :cx_json_to_cx,   [:string, :pointer], :pointer
  attach_function :cx_json_to_xml,  [:string, :pointer], :pointer
  attach_function :cx_json_to_ast,  [:string, :pointer], :pointer
  attach_function :cx_json_to_json, [:string, :pointer], :pointer
  attach_function :cx_json_to_yaml, [:string, :pointer], :pointer
  attach_function :cx_json_to_toml, [:string, :pointer], :pointer
  attach_function :cx_json_to_md,   [:string, :pointer], :pointer

  # YAML input
  attach_function :cx_yaml_to_cx,   [:string, :pointer], :pointer
  attach_function :cx_yaml_to_xml,  [:string, :pointer], :pointer
  attach_function :cx_yaml_to_ast,  [:string, :pointer], :pointer
  attach_function :cx_yaml_to_json, [:string, :pointer], :pointer
  attach_function :cx_yaml_to_yaml, [:string, :pointer], :pointer
  attach_function :cx_yaml_to_toml, [:string, :pointer], :pointer
  attach_function :cx_yaml_to_md,   [:string, :pointer], :pointer

  # TOML input
  attach_function :cx_toml_to_cx,   [:string, :pointer], :pointer
  attach_function :cx_toml_to_xml,  [:string, :pointer], :pointer
  attach_function :cx_toml_to_ast,  [:string, :pointer], :pointer
  attach_function :cx_toml_to_json, [:string, :pointer], :pointer
  attach_function :cx_toml_to_yaml, [:string, :pointer], :pointer
  attach_function :cx_toml_to_toml, [:string, :pointer], :pointer
  attach_function :cx_toml_to_md,   [:string, :pointer], :pointer

  # MD input
  attach_function :cx_md_to_cx,   [:string, :pointer], :pointer
  attach_function :cx_md_to_xml,  [:string, :pointer], :pointer
  attach_function :cx_md_to_ast,  [:string, :pointer], :pointer
  attach_function :cx_md_to_json, [:string, :pointer], :pointer
  attach_function :cx_md_to_yaml, [:string, :pointer], :pointer
  attach_function :cx_md_to_toml, [:string, :pointer], :pointer
  attach_function :cx_md_to_md,   [:string, :pointer], :pointer

  # ── helpers ─────────────────────────────────────────────────────────────────

  def self._call(fn_sym, input)
    err_ptr = FFI::MemoryPointer.new(:pointer)
    out = send(fn_sym, input, err_ptr)
    if out.null?
      ep = err_ptr.read_pointer
      msg = ep.null? ? 'unknown error' : ep.read_string.force_encoding('UTF-8')
      cx_free(ep) unless ep.null?
      raise RuntimeError, msg
    end
    s = out.read_string.force_encoding('UTF-8')
    cx_free(out)
    s
  end

  def self._call_bin(fn_sym, input)
    err_ptr = FFI::MemoryPointer.new(:pointer)
    out = send(fn_sym, input, err_ptr)
    if out.null?
      ep = err_ptr.read_pointer
      msg = ep.null? ? 'unknown error' : ep.read_string.force_encoding('UTF-8')
      cx_free(ep) unless ep.null?
      raise RuntimeError, msg
    end
    size = out.read_bytes(4).unpack1('V')
    payload = out.get_bytes(4, size)
    cx_free(out)
    payload
  end

  def self.ast_bin(cx_str)
    _call_bin(:cx_to_ast_bin, cx_str)
  end

  def self.events_bin(cx_str)
    _call_bin(:cx_to_events_bin, cx_str)
  end

  # ── public API ───────────────────────────────────────────────────────────────

  def self.version
    ptr = cx_version()
    s = ptr.read_string.force_encoding('UTF-8')
    cx_free(ptr)
    s
  end

  # CX input
  def self.to_cx        (src) = _call(:cx_to_cx,         src)
  def self.to_cx_compact(src) = _call(:cx_to_cx_compact, src)
  def self.ast_to_cx    (src) = _call(:cx_ast_to_cx,     src)
  def self.to_xml(src)  = _call(:cx_to_xml,  src)
  def self.to_ast(src)  = _call(:cx_to_ast,  src)
  def self.to_json(src) = _call(:cx_to_json, src)
  def self.to_yaml(src) = _call(:cx_to_yaml, src)
  def self.to_toml(src) = _call(:cx_to_toml, src)
  def self.to_md(src)   = _call(:cx_to_md,   src)

  # XML input
  def self.xml_to_cx(src)   = _call(:cx_xml_to_cx,   src)
  def self.xml_to_xml(src)  = _call(:cx_xml_to_xml,  src)
  def self.xml_to_ast(src)  = _call(:cx_xml_to_ast,  src)
  def self.xml_to_json(src) = _call(:cx_xml_to_json, src)
  def self.xml_to_yaml(src) = _call(:cx_xml_to_yaml, src)
  def self.xml_to_toml(src) = _call(:cx_xml_to_toml, src)
  def self.xml_to_md(src)   = _call(:cx_xml_to_md,   src)

  # JSON input
  def self.json_to_cx(src)   = _call(:cx_json_to_cx,   src)
  def self.json_to_xml(src)  = _call(:cx_json_to_xml,  src)
  def self.json_to_ast(src)  = _call(:cx_json_to_ast,  src)
  def self.json_to_json(src) = _call(:cx_json_to_json, src)
  def self.json_to_yaml(src) = _call(:cx_json_to_yaml, src)
  def self.json_to_toml(src) = _call(:cx_json_to_toml, src)
  def self.json_to_md(src)   = _call(:cx_json_to_md,   src)

  # YAML input
  def self.yaml_to_cx(src)   = _call(:cx_yaml_to_cx,   src)
  def self.yaml_to_xml(src)  = _call(:cx_yaml_to_xml,  src)
  def self.yaml_to_ast(src)  = _call(:cx_yaml_to_ast,  src)
  def self.yaml_to_json(src) = _call(:cx_yaml_to_json, src)
  def self.yaml_to_yaml(src) = _call(:cx_yaml_to_yaml, src)
  def self.yaml_to_toml(src) = _call(:cx_yaml_to_toml, src)
  def self.yaml_to_md(src)   = _call(:cx_yaml_to_md,   src)

  # TOML input
  def self.toml_to_cx(src)   = _call(:cx_toml_to_cx,   src)
  def self.toml_to_xml(src)  = _call(:cx_toml_to_xml,  src)
  def self.toml_to_ast(src)  = _call(:cx_toml_to_ast,  src)
  def self.toml_to_json(src) = _call(:cx_toml_to_json, src)
  def self.toml_to_yaml(src) = _call(:cx_toml_to_yaml, src)
  def self.toml_to_toml(src) = _call(:cx_toml_to_toml, src)
  def self.toml_to_md(src)   = _call(:cx_toml_to_md,   src)

  # MD input
  def self.md_to_cx(src)   = _call(:cx_md_to_cx,   src)
  def self.md_to_xml(src)  = _call(:cx_md_to_xml,  src)
  def self.md_to_ast(src)  = _call(:cx_md_to_ast,  src)
  def self.md_to_json(src) = _call(:cx_md_to_json, src)
  def self.md_to_yaml(src) = _call(:cx_md_to_yaml, src)
  def self.md_to_toml(src) = _call(:cx_md_to_toml, src)
  def self.md_to_md(src)   = _call(:cx_md_to_md,   src)

  # ── CXPath ──────────────────────────────────────────────────────────────────

  CXPredAttrExists     = Struct.new(:attr)
  CXPredAttrCmp        = Struct.new(:attr, :op, :val)
  CXPredChildExists    = Struct.new(:name)
  CXPredNot            = Struct.new(:inner)
  CXPredBoolAnd        = Struct.new(:left, :right)
  CXPredBoolOr         = Struct.new(:left, :right)
  CXPredPosition       = Struct.new(:pos, :is_last)
  CXPredFuncContains   = Struct.new(:attr, :val)
  CXPredFuncStartsWith = Struct.new(:attr, :val)
  CXStep               = Struct.new(:axis, :name, :preds)  # axis: :child | :descendant
  CXPathExpr           = Struct.new(:steps)

  # ── Lexer ──────────────────────────────────────────────────────────────────

  class CXLexer
    attr_reader :src, :pos
    attr_writer :pos

    def initialize(src)
      @src = src
      @pos = 0
    end

    def skip_ws
      @pos += 1 while @pos < @src.size && @src[@pos] == ' '
    end

    def peek_str(s)
      @src[@pos, s.size] == s
    end

    def eat_str(s)
      if peek_str(s)
        @pos += s.size
        true
      else
        false
      end
    end

    def eat_char(c)
      if @pos < @src.size && @src[@pos] == c
        @pos += 1
        true
      else
        false
      end
    end

    def read_ident
      start = @pos
      while @pos < @src.size
        c = @src[@pos]
        if c =~ /[[:alnum:]]/ || '_-.:%'.include?(c)
          @pos += 1
        else
          break
        end
      end
      @src[start, @pos - start]
    end

    def read_quoted
      raise ArgumentError, "CXPath parse error: expected ' at pos #{@pos}  expr: #{@src}" unless eat_char("'")
      start = @pos
      @pos += 1 while @pos < @src.size && @src[@pos] != "'"
      s = @src[start, @pos - start]
      raise ArgumentError, "CXPath parse error: unterminated string at pos #{@pos}  expr: #{@src}" unless eat_char("'")
      s
    end
  end

  # ── Parser ─────────────────────────────────────────────────────────────────

  def self.cxpath_parse(expr)
    l = CXLexer.new(expr)
    steps = _cxpath_parse_steps(l)
    if l.pos != l.src.size
      raise ArgumentError, "CXPath parse error: unexpected characters at pos #{l.pos}  expr: #{expr}"
    end
    raise ArgumentError, "CXPath parse error: empty expression  expr: #{expr}" if steps.empty?
    CXPathExpr.new(steps)
  end

  def self._cxpath_parse_steps(l)
    steps = []
    axis = :child
    if l.eat_str('//')
      axis = :descendant
    elsif l.eat_str('/')
      axis = :child
    end
    steps << _cxpath_parse_one_step(l, axis)
    loop do
      l.skip_ws
      if l.eat_str('//')
        steps << _cxpath_parse_one_step(l, :descendant)
      elsif l.eat_str('/')
        steps << _cxpath_parse_one_step(l, :child)
      else
        break
      end
    end
    steps
  end

  def self._cxpath_parse_one_step(l, axis)
    l.skip_ws
    name = if l.eat_char('*')
      ''
    else
      n = l.read_ident
      raise ArgumentError, "CXPath parse error: expected element name at pos #{l.pos}  expr: #{l.src}" if n.empty?
      n
    end
    preds = []
    loop do
      l.skip_ws
      if l.peek_str('[')
        preds << _cxpath_parse_pred_bracket(l)
      else
        break
      end
    end
    CXStep.new(axis, name, preds)
  end

  def self._cxpath_parse_pred_bracket(l)
    raise ArgumentError, "CXPath parse error: expected [ at pos #{l.pos}  expr: #{l.src}" unless l.eat_char('[')
    l.skip_ws
    pred = _cxpath_parse_pred_expr(l)
    l.skip_ws
    raise ArgumentError, "CXPath parse error: expected ] at pos #{l.pos}  expr: #{l.src}" unless l.eat_char(']')
    pred
  end

  def self._cxpath_parse_pred_expr(l)
    left = _cxpath_parse_pred_term(l)
    l.skip_ws
    saved = l.pos
    word = l.read_ident
    if word == 'or'
      l.skip_ws
      right = _cxpath_parse_pred_term(l)
      return CXPredBoolOr.new(left, right)
    end
    l.pos = saved
    left
  end

  def self._cxpath_parse_pred_term(l)
    left = _cxpath_parse_pred_factor(l)
    l.skip_ws
    saved = l.pos
    word = l.read_ident
    if word == 'and'
      l.skip_ws
      right = _cxpath_parse_pred_factor(l)
      return CXPredBoolAnd.new(left, right)
    end
    l.pos = saved
    left
  end

  def self._cxpath_parse_pred_factor(l)
    l.skip_ws
    # not(...)
    if l.peek_str('not(') || l.peek_str('not (')
      l.read_ident  # consume 'not'
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected ( after not  expr: #{l.src}" unless l.eat_char('(')
      l.skip_ws
      inner = _cxpath_parse_pred_expr(l)
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected ) after not(...)  expr: #{l.src}" unless l.eat_char(')')
      return CXPredNot.new(inner)
    end
    # contains(@attr, val)
    if l.peek_str('contains(')
      l.read_ident  # consume 'contains'
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected ( after contains  expr: #{l.src}" unless l.eat_char('(')
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected @attr in contains()  expr: #{l.src}" unless l.eat_char('@')
      attr = l.read_ident
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected , in contains()  expr: #{l.src}" unless l.eat_char(',')
      l.skip_ws
      val = _cxpath_parse_scalar_str(l)
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected ) after contains(...)  expr: #{l.src}" unless l.eat_char(')')
      return CXPredFuncContains.new(attr, val)
    end
    # starts-with(@attr, val)
    if l.peek_str('starts-with(')
      l.pos += 1 while l.pos < l.src.size && l.src[l.pos] != '('
      raise ArgumentError, "CXPath parse error: expected ( after starts-with  expr: #{l.src}" unless l.eat_char('(')
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected @attr in starts-with()  expr: #{l.src}" unless l.eat_char('@')
      attr = l.read_ident
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected , in starts-with()  expr: #{l.src}" unless l.eat_char(',')
      l.skip_ws
      val = _cxpath_parse_scalar_str(l)
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected ) after starts-with(...)  expr: #{l.src}" unless l.eat_char(')')
      return CXPredFuncStartsWith.new(attr, val)
    end
    # last()
    if l.peek_str('last()')
      l.pos += 6
      return CXPredPosition.new(0, true)
    end
    # (grouped expr)
    if l.peek_str('(')
      l.eat_char('(')
      l.skip_ws
      inner = _cxpath_parse_pred_expr(l)
      l.skip_ws
      raise ArgumentError, "CXPath parse error: expected ) at pos #{l.pos}  expr: #{l.src}" unless l.eat_char(')')
      return inner
    end
    # @attr comparison or existence
    if l.pos < l.src.size && l.src[l.pos] == '@'
      l.eat_char('@')
      attr = l.read_ident
      l.skip_ws
      op = _cxpath_parse_op(l)
      return CXPredAttrExists.new(attr) if op.empty?
      l.skip_ws
      val = _cxpath_parse_scalar_val(l)
      return CXPredAttrCmp.new(attr, op, val)
    end
    # integer position predicate
    if l.pos < l.src.size && l.src[l.pos] =~ /\d/
      start = l.pos
      l.pos += 1 while l.pos < l.src.size && l.src[l.pos] =~ /\d/
      return CXPredPosition.new(l.src[start, l.pos - start].to_i, false)
    end
    # bare name → child existence
    name = l.read_ident
    return CXPredChildExists.new(name) unless name.empty?
    raise ArgumentError, "CXPath parse error: unexpected character at pos #{l.pos}  expr: #{l.src}"
  end

  def self._cxpath_parse_op(l)
    %w[!= >= <= = > <].each do |op|
      return op if l.eat_str(op)
    end
    ''
  end

  def self._cxpath_autotype(s)
    return true  if s == 'true'
    return false if s == 'false'
    return nil   if s == 'null'
    begin
      return Integer(s)
    rescue ArgumentError, TypeError
      # not an integer
    end
    begin
      return Float(s)
    rescue ArgumentError, TypeError
      # not a float
    end
    s
  end

  def self._cxpath_parse_scalar_val(l)
    return l.read_quoted if l.peek_str("'")
    s = l.read_ident
    raise ArgumentError, "CXPath parse error: expected value at pos #{l.pos}  expr: #{l.src}" if s.empty?
    _cxpath_autotype(s)
  end

  def self._cxpath_parse_scalar_str(l)
    return l.read_quoted if l.peek_str("'")
    l.read_ident
  end

  # ── Evaluator ───────────────────────────────────────────────────────────────

  def self._cxpath_collect_step(ctx, expr, step_idx, result)
    return if step_idx >= expr.steps.size
    step = expr.steps[step_idx]
    if step.axis == :child
      candidates = ctx.items.select { |i| i.is_a?(Element) && (step.name.empty? || i.name == step.name) }
      candidates.each_with_index do |child, i|
        if _cxpath_preds_match(child, step.preds, candidates, i)
          if step_idx == expr.steps.size - 1
            result << child
          else
            _cxpath_collect_step(child, expr, step_idx + 1, result)
          end
        end
      end
    else
      _cxpath_collect_descendants(ctx, expr, step_idx, result)
    end
  end

  def self._cxpath_collect_descendants(ctx, expr, step_idx, result)
    step = expr.steps[step_idx]
    is_last = step_idx == expr.steps.size - 1
    candidates = ctx.items.select { |i| i.is_a?(Element) && (step.name.empty? || i.name == step.name) }
    candidates.each_with_index do |child, i|
      if _cxpath_preds_match(child, step.preds, candidates, i)
        if is_last
          result << child
        else
          _cxpath_collect_step(child, expr, step_idx + 1, result)
        end
      end
      # Always recurse deeper for descendant axis
      _cxpath_collect_descendants(child, expr, step_idx, result)
    end
    # Also descend into non-matching children for named steps
    if !step.name.empty?
      ctx.items.each do |child|
        if child.is_a?(Element) && child.name != step.name
          _cxpath_collect_descendants(child, expr, step_idx, result)
        end
      end
    end
  end

  def self._cxpath_preds_match(el, preds, siblings, idx)
    preds.all? { |p| _cxpath_pred_eval(el, p, siblings, idx) }
  end

  def self._cxpath_pred_eval(el, pred, siblings, idx)
    case pred
    when CXPredAttrExists
      !el.attr(pred.attr).nil?
    when CXPredAttrCmp
      v = el.attr(pred.attr)
      return false if v.nil?
      _cxpath_compare(v, pred.op, pred.val)
    when CXPredChildExists
      !el.get(pred.name).nil?
    when CXPredNot
      !_cxpath_pred_eval(el, pred.inner, siblings, idx)
    when CXPredBoolAnd
      _cxpath_pred_eval(el, pred.left, siblings, idx) &&
        _cxpath_pred_eval(el, pred.right, siblings, idx)
    when CXPredBoolOr
      _cxpath_pred_eval(el, pred.left, siblings, idx) ||
        _cxpath_pred_eval(el, pred.right, siblings, idx)
    when CXPredPosition
      if pred.is_last
        idx == siblings.size - 1
      else
        idx == pred.pos - 1
      end
    when CXPredFuncContains
      v = el.attr(pred.attr)
      !v.nil? && _cxpath_val_to_str(v).include?(pred.val)
    when CXPredFuncStartsWith
      v = el.attr(pred.attr)
      !v.nil? && _cxpath_val_to_str(v).start_with?(pred.val)
    else
      false
    end
  end

  def self._cxpath_val_to_str(v)
    return 'null'  if v.nil?
    return 'true'  if v == true
    return 'false' if v == false
    v.to_s
  end

  def self._cxpath_scalar_eq(a, b)
    # In Ruby, true/false are not subtypes of Integer, so no special-casing needed
    # But guard against comparing bool with non-bool
    a_bool = (a == true || a == false)
    b_bool = (b == true || b == false)
    return false if a_bool != b_bool
    if (a.is_a?(Integer) || a.is_a?(Float)) && (b.is_a?(Integer) || b.is_a?(Float))
      return a.to_f == b.to_f
    end
    a == b
  end

  def self._cxpath_to_f64(v)
    raise ArgumentError, "CXPath: numeric comparison requires numeric value, got bool: #{v}" if v == true || v == false
    raise ArgumentError, "CXPath: numeric comparison requires numeric attribute value, got: #{v.inspect}" unless v.is_a?(Integer) || v.is_a?(Float)
    v.to_f
  end

  def self._cxpath_compare(actual, op, expected)
    case op
    when '='  then _cxpath_scalar_eq(actual, expected)
    when '!=' then !_cxpath_scalar_eq(actual, expected)
    else
      a = _cxpath_to_f64(actual)
      b = _cxpath_to_f64(expected)
      case op
      when '>'  then a > b
      when '<'  then a < b
      when '>=' then a >= b
      when '<=' then a <= b
      else false
      end
    end
  end

  # ── cxpath_elem_matches (for transform_all) ─────────────────────────────────

  def self._cxpath_elem_matches(el, expr)
    return false if expr.steps.empty?
    last = expr.steps.last
    return false if !last.name.empty? && last.name != el.name
    non_pos = last.preds.reject { |p| p.is_a?(CXPredPosition) }
    _cxpath_preds_match(el, non_pos, [], 0)
  end

  # ── Transform helpers ───────────────────────────────────────────────────────

  def self._elem_detached(e)
    Element.new(e.name,
      attrs:     e.attrs.map { |a| Attr.new(a.name, a.value, a.data_type) },
      items:     e.items.dup,
      anchor:    e.anchor,
      merge:     e.merge,
      data_type: e.data_type)
  end

  def self._doc_replace_at(d, idx, el)
    new_elems = d.elements.dup
    new_elems[idx] = el
    Document.new(elements: new_elems, prolog: d.prolog.dup, doctype: d.doctype)
  end

  def self._elem_replace_item_at(e, idx, child)
    new_items = e.items.dup
    new_items[idx] = child
    Element.new(e.name,
      attrs:     e.attrs,
      items:     new_items,
      anchor:    e.anchor,
      merge:     e.merge,
      data_type: e.data_type)
  end

  def self._path_copy_element(e, parts, &f)
    e.items.each_with_index do |item, i|
      next unless item.is_a?(Element) && item.name == parts[0]
      if parts.size == 1
        return _elem_replace_item_at(e, i, f.call(_elem_detached(item)))
      end
      updated = _path_copy_element(item, parts[1..], &f)
      return updated ? _elem_replace_item_at(e, i, updated) : nil
    end
    nil
  end

  def self._rebuild_node(node, expr, &f)
    return node unless node.is_a?(Element)
    new_items = node.items.map { |item| _rebuild_node(item, expr, &f) }
    new_el = Element.new(node.name,
      attrs:     node.attrs,
      items:     new_items,
      anchor:    node.anchor,
      merge:     node.merge,
      data_type: node.data_type)
    if _cxpath_elem_matches(new_el, expr)
      f.call(_elem_detached(new_el))
    else
      new_el
    end
  end

  # ── Binary wire protocol ─────────────────────────────────────────────────────

  class BufReader
    def initialize(data)
      @data = data.b
      @pos  = 0
    end

    def u8
      v = @data.getbyte(@pos)
      @pos += 1
      v
    end

    def u16
      v = @data[@pos, 2].unpack1('v')
      @pos += 2
      v
    end

    def u32
      v = @data[@pos, 4].unpack1('V')
      @pos += 4
      v
    end

    def str_
      n = u32
      s = @data[@pos, n].force_encoding('UTF-8')
      @pos += n
      s
    end

    def optstr
      u8 == 1 ? str_ : nil
    end
  end

  def self._bin_coerce(type_str, value_str)
    case type_str
    when 'int'   then value_str.to_i
    when 'float' then value_str.to_f
    when 'bool'  then value_str.start_with?('t')
    when 'null'  then nil
    else              value_str
    end
  end

  def self._bin_read_attr(b)
    name      = b.str_
    value_str = b.str_
    t         = b.str_
    dt        = (t == 'string') ? nil : t
    Attr.new(name, _bin_coerce(t, value_str), dt)
  end

  def self._bin_read_node(b)
    tid = b.u8
    case tid
    when 0x01
      name   = b.str_
      anchor = b.optstr
      dt     = b.optstr
      merge  = b.optstr
      attrs  = Array.new(b.u16) { _bin_read_attr(b) }
      items  = Array.new(b.u16) { _bin_read_node(b) }
      Element.new(name, attrs: attrs, items: items, anchor: anchor, merge: merge, data_type: dt)
    when 0x02
      TextNode.new(b.str_)
    when 0x03
      t = b.str_; ScalarNode.new(t, _bin_coerce(t, b.str_))
    when 0x04
      Comment.new(b.str_)
    when 0x05
      RawText.new(b.str_)
    when 0x06
      EntityRef.new(b.str_)
    when 0x07
      Alias.new(b.str_)
    when 0x08
      PI.new(b.str_, b.optstr)
    when 0x09
      XMLDecl.new(version: b.str_, encoding: b.optstr, standalone: b.optstr)
    when 0x0A
      CXDirective.new(attrs: Array.new(b.u16) { _bin_read_attr(b) })
    when 0x0C
      BlockContent.new(items: Array.new(b.u16) { _bin_read_node(b) })
    else
      TextNode.new('')
    end
  end

  def self.decode_ast(data)
    b = BufReader.new(data)
    _ver    = b.u8
    prolog  = Array.new(b.u16) { _bin_read_node(b) }
    elements = Array.new(b.u16) { _bin_read_node(b) }
    Document.new(prolog: prolog, elements: elements)
  end

  # ── StreamEvent ───────────────────────────────────────────────────────────────

  class StreamEvent
    attr_accessor :type, :name, :attrs, :data_type, :anchor, :merge,
                  :value, :target, :data

    def initialize(type:)
      @type      = type
      @name      = nil
      @attrs     = []
      @data_type = nil
      @anchor    = nil
      @merge     = nil
      @value     = nil
      @target    = nil
      @data      = nil
    end

    def start_element?(name = nil)
      @type == 'StartElement' && (name.nil? || @name == name)
    end

    def end_element?(name = nil)
      @type == 'EndElement' && (name.nil? || @name == name)
    end
  end

  EVT_TYPES_ = {
    0x01 => 'StartDoc', 0x02 => 'EndDoc', 0x03 => 'StartElement',
    0x04 => 'EndElement', 0x05 => 'Text', 0x06 => 'Scalar',
    0x07 => 'Comment', 0x08 => 'PI', 0x09 => 'EntityRef',
    0x0A => 'RawText', 0x0B => 'Alias',
  }.freeze

  def self.decode_events(data)
    b      = BufReader.new(data)
    count  = b.u32
    events = Array.new(count) do
      tid = b.u8
      t   = EVT_TYPES_.fetch(tid, 'Unknown')
      e   = StreamEvent.new(type: t)
      case tid
      when 0x03
        e.name      = b.str_
        e.anchor    = b.optstr
        e.data_type = b.optstr
        _merge      = b.optstr
        e.merge     = _merge
        e.attrs     = Array.new(b.u16) do
          nm      = b.str_
          val_str = b.str_
          typ     = b.str_
          Attr.new(nm, _bin_coerce(typ, val_str), typ == 'string' ? nil : typ)
        end
      when 0x04
        e.name  = b.str_
      when 0x05, 0x07, 0x0A
        e.value = b.str_
      when 0x06
        dt = b.str_; e.data_type = dt; e.value = _bin_coerce(dt, b.str_)
      when 0x08
        e.target = b.str_; e.data = b.optstr
      when 0x09, 0x0B
        e.value = b.str_
      end
      e
    end
    events
  end

  # ── Document API ─────────────────────────────────────────────────────────────

  require 'json'

  # ── Node types ─────────────────────────────────────────────────────────────

  class Attr
    attr_accessor :name, :value, :data_type
    def initialize(name, value, data_type = nil)
      @name, @value, @data_type = name, value, data_type
    end
  end

  class TextNode
    attr_accessor :value
    def initialize(v); @value = v; end
  end

  class ScalarNode
    attr_accessor :data_type, :value
    def initialize(dt, v); @data_type, @value = dt, v; end
  end

  class Comment
    attr_accessor :value
    def initialize(v); @value = v; end
  end

  class RawText
    attr_accessor :value
    def initialize(v); @value = v; end
  end

  class EntityRef
    attr_accessor :name
    def initialize(n); @name = n; end
  end

  class Alias
    attr_accessor :name
    def initialize(n); @name = n; end
  end

  class PI
    attr_accessor :target, :data
    def initialize(target, data = nil); @target, @data = target, data; end
  end

  class XMLDecl
    attr_accessor :version, :encoding, :standalone
    def initialize(version: '1.0', encoding: nil, standalone: nil)
      @version, @encoding, @standalone = version, encoding, standalone
    end
  end

  class CXDirective
    attr_accessor :attrs
    def initialize(attrs: []); @attrs = attrs; end
  end

  class DoctypeDecl
    attr_accessor :name, :external_id, :int_subset
    def initialize(name, external_id: nil, int_subset: [])
      @name, @external_id, @int_subset = name, external_id, int_subset
    end
  end

  class BlockContent
    attr_accessor :items
    def initialize(items: []); @items = items; end
  end

  class Element
    attr_accessor :name, :anchor, :merge, :data_type, :attrs, :items

    def initialize(name, attrs: [], items: [], anchor: nil, merge: nil, data_type: nil)
      @name       = name
      @attrs      = attrs
      @items      = items
      @anchor     = anchor
      @merge      = merge
      @data_type  = data_type
    end

    # Returns attribute value by name, or nil
    def attr(name)
      a = @attrs.find { |x| x.name == name }
      a&.value
    end

    # Returns concatenated text and scalar child content
    def text
      parts = []
      @items.each do |item|
        case item
        when TextNode   then parts << item.value
        when ScalarNode then parts << (item.value.nil? ? 'null' : item.value.to_s)
        end
      end
      parts.join(' ')
    end

    # Returns value of first Scalar child, or nil
    def scalar
      s = @items.find { |i| i.is_a?(ScalarNode) }
      s&.value
    end

    # Returns all child Elements
    def children
      @items.select { |i| i.is_a?(Element) }
    end

    # First child Element with given name
    def get(name)
      @items.find { |i| i.is_a?(Element) && i.name == name }
    end

    # All child Elements with given name
    def get_all(name)
      @items.select { |i| i.is_a?(Element) && i.name == name }
    end

    # All descendant Elements with given name (depth-first)
    def find_all(name)
      result = []
      @items.each do |item|
        next unless item.is_a?(Element)
        result << item if item.name == name
        result.concat(item.find_all(name))
      end
      result
    end

    # First descendant Element with given name (depth-first)
    def find_first(name)
      @items.each do |item|
        next unless item.is_a?(Element)
        return item if item.name == name
        found = item.find_first(name)
        return found unless found.nil?
      end
      nil
    end

    # Navigate by slash-separated path
    def at(path)
      parts = path.split('/').reject(&:empty?)
      cur = self
      parts.each do |part|
        return nil if cur.nil?
        cur = cur.get(part)
      end
      cur
    end

    # Mutation
    def set_attr(name, value, data_type = nil)
      existing = @attrs.find { |a| a.name == name }
      if existing
        existing.value     = value
        existing.data_type = data_type
      else
        @attrs << Attr.new(name, value, data_type)
      end
    end

    def remove_attr(name)
      @attrs.reject! { |a| a.name == name }
    end

    def append(node)
      @items << node
    end

    def prepend(node)
      @items.unshift(node)
    end

    def insert(index, node)
      @items.insert(index, node)
    end

    def remove(node)
      @items.reject! { |i| i.equal?(node) }
    end

    # Remove all direct child Elements with the given name (mutating)
    def remove_child(name)
      @items.reject! { |i| i.is_a?(Element) && i.name == name }
    end

    # Remove child node at index (no-op if out of bounds) (mutating)
    def remove_at(index)
      return unless index >= 0 && index < @items.size
      @items.delete_at(index)
    end

    # First Element matching a CXPath expression (searches subtree of self)
    def select(expr)
      select_all(expr).first
    end

    # All Elements matching a CXPath expression (searches subtree of self)
    def select_all(expr)
      cx = CXLib.cxpath_parse(expr)
      result = []
      CXLib._cxpath_collect_step(self, cx, 0, result)
      result
    end

    def to_cx
      CXLib._emit_element(self, 0).rstrip("\n")
    end
  end

  class Document
    attr_accessor :elements, :prolog, :doctype

    def initialize(elements: [], prolog: [], doctype: nil)
      @elements = elements
      @prolog   = prolog
      @doctype  = doctype
    end

    # First top-level Element
    def root
      @elements.find { |e| e.is_a?(Element) }
    end

    # First top-level Element with given name
    def get(name)
      @elements.find { |e| e.is_a?(Element) && e.name == name }
    end

    # Navigate by slash-separated path from root
    def at(path)
      parts = path.split('/').reject(&:empty?)
      return root if parts.empty?
      cur = get(parts[0])
      return cur if parts.size == 1 || cur.nil?
      cur.at(parts[1..].join('/'))
    end

    # All descendant Elements with given name
    def find_all(name)
      result = []
      @elements.each do |e|
        next unless e.is_a?(Element)
        result << e if e.name == name
        result.concat(e.find_all(name))
      end
      result
    end

    # First descendant Element with given name
    def find_first(name)
      @elements.each do |e|
        next unless e.is_a?(Element)
        return e if e.name == name
        found = e.find_first(name)
        return found unless found.nil?
      end
      nil
    end

    def append(node)
      @elements << node
    end

    def prepend(node)
      @elements.unshift(node)
    end

    # First Element matching a CXPath expression
    def select(expr)
      select_all(expr).first
    end

    # All Elements matching a CXPath expression
    def select_all(expr)
      cx = CXLib.cxpath_parse(expr)
      vroot = Element.new('#document', items: @elements.dup)
      result = []
      CXLib._cxpath_collect_step(vroot, cx, 0, result)
      result
    end

    # Return new Document with element at path replaced by f(element) (immutable)
    def transform(path, &f)
      parts = path.split('/').reject(&:empty?)
      return self if parts.empty?
      @elements.each_with_index do |node, i|
        next unless node.is_a?(Element) && node.name == parts[0]
        if parts.size == 1
          return CXLib._doc_replace_at(self, i, f.call(CXLib._elem_detached(node)))
        end
        updated = CXLib._path_copy_element(node, parts[1..], &f)
        return updated ? CXLib._doc_replace_at(self, i, updated) : self
      end
      self
    end

    # Return new Document with all matching elements replaced by f(element) (immutable)
    def transform_all(expr, &f)
      cx = CXLib.cxpath_parse(expr)
      new_elements = @elements.map { |n| CXLib._rebuild_node(n, cx, &f) }
      Document.new(elements: new_elements, prolog: @prolog.dup, doctype: @doctype)
    end

    def to_cx
      CXLib._emit_doc(self)
    end

    def to_xml  = CXLib.to_xml(to_cx)
    def to_json = CXLib.to_json(to_cx)
    def to_yaml = CXLib.to_yaml(to_cx)
    def to_toml = CXLib.to_toml(to_cx)
    def to_md   = CXLib.to_md(to_cx)
  end

  # ── Deserialization: AST JSON → native types ───────────────────────────────

  def self.node_from_hash(h)
    case h['type']
    when 'Element'
      Element.new(
        h['name'],
        attrs:     (h['attrs'] || []).map { |a| Attr.new(a['name'], a['value'], a['dataType']) },
        items:     (h['items'] || []).map { |n| node_from_hash(n) },
        anchor:    h['anchor'],
        merge:     h['merge'],
        data_type: h['dataType'],
      )
    when 'Text'       then TextNode.new(h['value'])
    when 'Scalar'     then ScalarNode.new(h['dataType'], h['value'])
    when 'Comment'    then Comment.new(h['value'])
    when 'RawText'    then RawText.new(h['value'])
    when 'EntityRef'  then EntityRef.new(h['name'])
    when 'Alias'      then Alias.new(h['name'])
    when 'PI'         then PI.new(h['target'], h['data'])
    when 'XMLDecl'
      XMLDecl.new(version: h.fetch('version', '1.0'), encoding: h['encoding'], standalone: h['standalone'])
    when 'CXDirective'
      CXDirective.new(attrs: (h['attrs'] || []).map { |a| Attr.new(a['name'], a['value']) })
    when 'DoctypeDecl'
      DoctypeDecl.new(h['name'], external_id: h['externalID'], int_subset: h.fetch('intSubset', []))
    when 'BlockContent'
      BlockContent.new(items: (h['items'] || []).map { |n| node_from_hash(n) })
    else
      TextNode.new(h.to_s)
    end
  end

  def self.doc_from_hash(d)
    doctype = nil
    if d['doctype']
      dt = d['doctype']
      doctype = DoctypeDecl.new(dt['name'], external_id: dt['externalID'], int_subset: dt.fetch('intSubset', []))
    end
    Document.new(
      prolog:   (d['prolog']   || []).map { |n| node_from_hash(n) },
      doctype:  doctype,
      elements: (d['elements'] || []).map { |n| node_from_hash(n) },
    )
  end

  # ── Parse functions ────────────────────────────────────────────────────────

  def self.parse(cx_str)
    decode_ast(ast_bin(cx_str))
  end

  def self.parse_xml(xml_str)
    doc_from_hash(JSON.parse(xml_to_ast(xml_str)))
  end

  def self.parse_json(json_str)
    doc_from_hash(JSON.parse(json_to_ast(json_str)))
  end

  def self.parse_yaml(yaml_str)
    doc_from_hash(JSON.parse(yaml_to_ast(yaml_str)))
  end

  def self.parse_toml(toml_str)
    doc_from_hash(JSON.parse(toml_to_ast(toml_str)))
  end

  def self.parse_md(md_str)
    doc_from_hash(JSON.parse(md_to_ast(md_str)))
  end

  def self.stream(cx_str)
    decode_events(events_bin(cx_str))
  end

  # ── Data binding ──────────────────────────────────────────────────────────

  def self.loads(cx_str)
    JSON.parse(to_json(cx_str))
  end

  def self.loads_xml(xml_str)
    JSON.parse(xml_to_json(xml_str))
  end

  def self.loads_json(json_str)
    JSON.parse(json_to_json(json_str))
  end

  def self.loads_yaml(yaml_str)
    JSON.parse(yaml_to_json(yaml_str))
  end

  def self.loads_toml(toml_str)
    JSON.parse(toml_to_json(toml_str))
  end

  def self.loads_md(md_str)
    JSON.parse(md_to_json(md_str))
  end

  def self.dumps(data)
    json_to_cx(JSON.generate(data))
  end

  # ── CX emitter ────────────────────────────────────────────────────────────

  DATE_RE_     = /^\d{4}-\d{2}-\d{2}$/
  DATETIME_RE_ = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
  HEX_RE_      = /^0[xX][0-9a-fA-F]+$/

  def self._would_autotype(s)
    return false if s.include?(' ')
    return true  if HEX_RE_.match?(s)
    begin
      Integer(s, 10)
      return true
    rescue ArgumentError, TypeError
      # not an integer
    end
    if s.include?('.') || s.downcase.include?('e')
      begin
        Float(s)
        return true
      rescue ArgumentError, TypeError
        # not a float
      end
    end
    return true if %w[true false null].include?(s)
    return true if DATETIME_RE_.match?(s)
    return true if DATE_RE_.match?(s)
    false
  end

  def self._cx_choose_quote(s)
    return "'#{s}'"   unless s.include?("'")
    return "\"#{s}\"" unless s.include?('"')
    return "'''#{s}'''" unless s.include?("'''")
    "\"#{s}\""
  end

  def self._cx_quote_text(s)
    needs = s.start_with?(' ') || s.end_with?(' ') ||
            s.include?('  ')   || s.include?("\n") || s.include?("\t") ||
            s.include?('[')    || s.include?(']')  || s.include?('&') ||
            s.start_with?(':') || s.start_with?("'") || s.start_with?('"') ||
            _would_autotype(s)
    needs ? _cx_choose_quote(s) : s
  end

  def self._cx_quote_attr(s)
    return "'#{s}'" if s.empty? || s.include?(' ') || s.include?("'") || s.include?('"')
    s
  end

  def self._emit_scalar(s)
    v = s.value
    return 'null'  if v.nil?
    return (v ? 'true' : 'false') if v == true || v == false
    if v.is_a?(Integer)
      return v.to_s
    end
    if v.is_a?(Float)
      f = v.to_s
      return (f.include?('.') || f.downcase.include?('e')) ? f : "#{f}.0"
    end
    v.to_s
  end

  def self._emit_attr(a)
    dt = a.data_type
    if dt == 'int'
      return "#{a.name}=#{a.value.to_i}"
    end
    if dt == 'float'
      f = a.value.to_f.to_s
      v = (f.include?('.') || f.downcase.include?('e')) ? f : "#{f}.0"
      return "#{a.name}=#{v}"
    end
    if dt == 'bool'
      return "#{a.name}=#{a.value ? 'true' : 'false'}"
    end
    if dt == 'null'
      return "#{a.name}=null"
    end
    # string attr — quote if would autotype
    s = a.value.to_s
    v = _would_autotype(s) ? _cx_choose_quote(s) : _cx_quote_attr(s)
    "#{a.name}=#{v}"
  end

  def self._emit_inline(node)
    case node
    when TextNode
      node.value.strip.empty? ? '' : _cx_quote_text(node.value)
    when ScalarNode
      _emit_scalar(node)
    when EntityRef
      "&#{node.name};"
    when RawText
      "[##{node.value}#]"
    when Element
      _emit_element(node, 0).rstrip("\n")
    when BlockContent
      inner = node.items.map do |n|
        n.is_a?(TextNode) ? n.value : _emit_element(n, 0).rstrip("\n")
      end.join
      "[|#{inner}|]"
    else
      ''
    end
  end

  def self._emit_element(e, depth)
    ind = '  ' * depth
    has_child_elems = e.items.any? { |i| i.is_a?(Element) }
    has_text        = e.items.any? { |i| i.is_a?(TextNode) || i.is_a?(ScalarNode) ||
                                         i.is_a?(EntityRef) || i.is_a?(RawText) }
    is_multiline    = has_child_elems && !has_text

    meta_parts = []
    meta_parts << "&#{e.anchor}" if e.anchor
    meta_parts << "*#{e.merge}"  if e.merge
    meta_parts << ":#{e.data_type}" if e.data_type
    e.attrs.each { |a| meta_parts << _emit_attr(a) }
    meta = meta_parts.empty? ? '' : ' ' + meta_parts.join(' ')

    if is_multiline
      lines = ["#{ind}[#{e.name}#{meta}\n"]
      e.items.each { |item| lines << _emit_node(item, depth + 1) }
      lines << "#{ind}]\n"
      return lines.join
    end

    if e.items.empty? && meta.empty?
      return "#{ind}[#{e.name}]\n"
    end

    body_parts = e.items.map { |i| _emit_inline(i) }.reject(&:empty?)
    body = body_parts.join(' ')
    sep  = body.empty? ? '' : ' '
    "#{ind}[#{e.name}#{meta}#{sep}#{body}]\n"
  end

  def self._emit_node(node, depth)
    ind = '  ' * depth
    case node
    when Element
      _emit_element(node, depth)
    when TextNode
      _cx_quote_text(node.value)
    when ScalarNode
      _emit_scalar(node)
    when Comment
      "#{ind}[-#{node.value}]\n"
    when RawText
      "#{ind}[##{node.value}#]\n"
    when EntityRef
      "&#{node.name};"
    when Alias
      "#{ind}[*#{node.name}]\n"
    when BlockContent
      inner = node.items.map { |i| _emit_node(i, 0) }.join
      "#{ind}[|#{inner}|]\n"
    when PI
      data = node.data ? " #{node.data}" : ''
      "#{ind}[?#{node.target}#{data}]\n"
    when XMLDecl
      parts = ["version=#{node.version}"]
      parts << "encoding=#{node.encoding}"   if node.encoding
      parts << "standalone=#{node.standalone}" if node.standalone
      "[?xml #{parts.join(' ')}]\n"
    when CXDirective
      attrs = node.attrs.map { |a| "#{a.name}=#{_cx_quote_attr(a.value.to_s)}" }.join(' ')
      "[?cx #{attrs}]\n"
    when DoctypeDecl
      ext = ''
      if node.external_id
        if node.external_id['public']
          pub = node.external_id['public']
          sys = node.external_id.fetch('system', '')
          ext = " PUBLIC '#{pub}' '#{sys}'"
        elsif node.external_id['system']
          ext = " SYSTEM '#{node.external_id['system']}'"
        end
      end
      "[!DOCTYPE #{node.name}#{ext}]\n"
    else
      ''
    end
  end

  def self._emit_doc(doc)
    parts = []
    doc.prolog.each   { |node| parts << _emit_node(node, 0) }
    parts << _emit_node(doc.doctype, 0) if doc.doctype
    doc.elements.each { |node| parts << _emit_node(node, 0) }
    parts.join.rstrip("\n")
  end

  # Internal helpers (indicated by _ prefix convention; not made private so
  # they remain accessible from nested class instance methods like Document#to_cx)
end
