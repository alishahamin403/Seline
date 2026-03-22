import Foundation

enum QueryType {
    case action(ActionType)
    case search
    case question
    case counting(CountingQueryParameters)
    case comparison(ComparisonQueryParameters)
    case temporal(TemporalQueryParameters)
}
