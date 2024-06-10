pub enum CostFunctionRuleSet {
    GORLITZ,
}

pub fn get_cost_function(
    rule_set: CostFunctionRuleSet
) -> Fn(i32, Point, MultiPolygon, MultiPolygon) -> i32 {
    match rule_set {
        GORLITZ => return |time: i32| time * 2,
    }
}
