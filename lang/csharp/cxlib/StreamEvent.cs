using System.Collections.Generic;

namespace CX;

/// <summary>A single event from the CX streaming (events) decoder.</summary>
public class StreamEvent
{
    public string Type { get; set; } = "";
    public string? Name { get; set; }
    public string? Anchor { get; set; }
    public string? DataType { get; set; }
    public string? Merge { get; set; }
    public List<Attr> Attrs { get; set; } = new();
    public object? Value { get; set; }
    public string? Target { get; set; }
    public string? Data { get; set; }
}
