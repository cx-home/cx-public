package cx;

import java.util.List;

/**
 * A single event produced by the CX streaming (SAX-like) parser.
 *
 * Which fields are populated depends on the event type:
 *
 *   StartDoc   — no fields
 *   EndDoc     — no fields
 *   StartElement — name, anchor, dataType, merge, attrs
 *   EndElement — name
 *   Text       — value (String)
 *   Scalar     — dataType, value (coerced: Long/Double/Boolean/null/String)
 *   Comment    — value (String)
 *   PI         — target, data (nullable)
 *   EntityRef  — value (String)
 *   RawText    — value (String)
 *   Alias      — value (String)
 */
public class StreamEvent {
    /** Event type name, e.g. "StartElement", "Text", "Scalar", … */
    public String type;

    /** Element name (StartElement, EndElement). */
    public String name;

    /** Anchor (StartElement only, may be null). */
    public String anchor;

    /** Data type annotation (StartElement, Scalar; may be null). */
    public String dataType;

    /** Merge target (StartElement only, may be null). */
    public String merge;

    /** Attributes (StartElement only; empty list if none). */
    public List<Attr> attrs;

    /**
     * Text or scalar value.
     * Text/Comment/RawText/EntityRef/Alias → String
     * Scalar → Long | Double | Boolean | null | String
     */
    public Object value;

    /** PI target (PI only). */
    public String target;

    /** PI data (PI only, may be null). */
    public String data;

    public StreamEvent(String type) {
        this.type = type;
    }

    @Override
    public String toString() {
        return "StreamEvent{type=" + type
                + (name     != null ? ", name="     + name     : "")
                + (anchor   != null ? ", anchor="   + anchor   : "")
                + (dataType != null ? ", dataType=" + dataType : "")
                + (merge    != null ? ", merge="    + merge    : "")
                + (attrs    != null ? ", attrs="    + attrs    : "")
                + (value    != null ? ", value="    + value    : "")
                + (target   != null ? ", target="   + target   : "")
                + (data     != null ? ", data="     + data     : "")
                + '}';
    }
}
