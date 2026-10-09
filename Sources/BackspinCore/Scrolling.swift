import CoreGraphics

/// Negates the vertical (axis 1) and/or horizontal (axis 2) scroll deltas.
public func flip(_ event: CGEvent, vertical: Bool, horizontal: Bool) {
    // Read everything first: setting the line delta makes the system recompute the others.
    let line1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let line2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let sign1: Int64 = vertical ? -1 : 1
    let sign2: Int64 = horizontal ? -1 : 1

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: sign1 * line1)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: sign2 * line2)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(sign1) * fixed1)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(sign2) * fixed2)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: sign1 * point1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: sign2 * point2)
}
