package cxlib

// Stream returns all streaming events for a CX input string.
func Stream(cxStr string) ([]StreamEvent, error) {
	data, err := ToEventsBin(cxStr)
	if err != nil {
		return nil, err
	}
	return decodeEvents(data)
}
