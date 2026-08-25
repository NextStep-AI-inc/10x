enum SessionRuntimeState: Equatable {
    case loading
    case idle
    case streaming
    case stopped(code: Int32?, stderrTail: String)
    case failed(String)
}
