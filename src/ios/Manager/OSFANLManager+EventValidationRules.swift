import FirebaseAnalytics

typealias ValidationMethod = (InputParameterData?, inout [InputItemData]?) throws -> Void

extension OSFANLManager {
    convenience init(_ inputTransformer: OSFANLInputTransformable) {
        let eventValidationRulesDictionary = [
            AnalyticsEventAddPaymentInfo: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventAddShippingInfo: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventAddToCart: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventAddToWishlist: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventBeginCheckout: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventPurchase: Self.validatePurchaseParameters(eventData:itemsData:),
            AnalyticsEventRefund: Self.validateRefundParameters(eventData:itemsData:),
            AnalyticsEventRemoveFromCart: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventSelectItem: Self.validateOneItemParameters(eventData:itemsData:),
            AnalyticsEventSelectPromotion: Self.validateSelectPromotionParameters(eventData:itemsData:),
            AnalyticsEventViewCart: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventViewItem: Self.validateValueCurrencyAndMultipleItemsParameters(eventData:itemsData:),
            AnalyticsEventViewItemList: Self.validateViewItemListParameters(eventData:itemsData:),
            AnalyticsEventViewPromotion: Self.validateOneItemParameters(eventData:itemsData:)
        ]
        
        let eventValidator = OSFANLEventValidator(eventValidatorMapping: eventValidationRulesDictionary)
        self.init(inputTransformer, eventValidator)
    }
}

private extension OSFANLManager {
    struct ParameterToValidate: OptionSet {
        let rawValue: Int
        
        static let currency         = Self(rawValue: 1 << 0)    // required if value is set
        static let shipping         = Self(rawValue: 1 << 1)    // always optional
        static let tax              = Self(rawValue: 1 << 2)    // always optional
        static let transactionId    = Self(rawValue: 1 << 3)    // always required
        static let value            = Self(rawValue: 1 << 4)    // optional
        
        static let currencyAndValue: Self = [.currency, .value]
    }

    enum ItemsRequired {
        case none
        case one
        case atLeastOne
    }
    
    static func validate(_ eventData: InputParameterData?, _ itemsData: inout [InputItemData]?, parameters: ParameterToValidate? = nil, itemsRequired: ItemsRequired) throws {
        // Validate parameters first
        if let parameters {
            if parameters.contains(.currencyAndValue) {
                let valueContainsValue = try self.validate(dataField: .value, eventData)
                try self.validate(dataField: .currency, isRequired: valueContainsValue, eventData)
            }
            if parameters.contains(.transactionId) {
                try self.validate(dataField: .transactionId, isRequired: true, eventData)
            }
            if parameters.contains(.shipping) {
                try self.validate(dataField: .shipping, eventData)
            }
            if parameters.contains(.tax) {
                try self.validate(dataField: .tax, eventData)
            }
        }
        
        if itemsRequired != .none, itemsData?.count ?? 0 < 1 { throw OSFANLError.missing(OSFANLInputDataFieldKey.items.rawValue) }
        
        if case .one = itemsRequired, let nonNilItemsData = itemsData, nonNilItemsData.count > 1 {
            itemsData?.removeLast(nonNilItemsData.count - 1)
        }
        
        if let eventData, let nonNilItemsData = itemsData {
            let itemListKey: [String] = [OSFANLInputDataFieldKey.itemListId, .itemListName].map(\.rawValue).filter { eventData.keys.contains($0) }
            
            if !itemListKey.isEmpty {
                for (index, itemData) in nonNilItemsData.enumerated() where itemData.keys.contains(where: { itemListKey.contains($0) }) {
                    if let firstItemListKey = itemListKey.first {
                        itemsData?[index][firstItemListKey] = nil
                        if let lastItemListKey = itemListKey.last, lastItemListKey != firstItemListKey {
                            itemsData?[index][lastItemListKey] = nil
                        }
                    }
                }
            }
        }
    }
    
    private static func validateValueCurrencyAndMultipleItemsParameters(eventData: InputParameterData?, itemsData: inout [InputItemData]?) throws {
        try self.validate(eventData, &itemsData, parameters: .currencyAndValue, itemsRequired: .atLeastOne)
    }
    
    private static func validatePurchaseParameters(eventData: InputParameterData?, itemsData: inout [InputItemData]?) throws {
        try self.validate(eventData, &itemsData, parameters: [.currencyAndValue, .transactionId, .shipping, .tax], itemsRequired: .atLeastOne)
    }
    
    private static func validateRefundParameters(eventData: InputParameterData?, itemsData: inout [InputItemData]?) throws {
        try self.validate(eventData, &itemsData, parameters: [.currencyAndValue, .transactionId, .shipping, .tax], itemsRequired: .none)
    }
    
    private static func validateOneItemParameters(eventData: InputParameterData?, itemsData: inout [InputItemData]?) throws {
        try self.validate(eventData, &itemsData, itemsRequired: .one)
    }
    
    private static func validateSelectPromotionParameters(eventData: InputParameterData?, itemsData: inout [InputItemData]?) throws {
        try self.validate(eventData, &itemsData, itemsRequired: .none)
    }
    
    private static func validateViewItemListParameters(eventData: InputParameterData?, itemsData: inout [InputItemData]?) throws {
        try self.validate(eventData, &itemsData, itemsRequired: .atLeastOne)
    }
    
    @discardableResult
    private static func validate(dataField: OSFANLInputDataFieldKey, isRequired: Bool = false, _ eventData: InputParameterData?) throws -> Bool {
        func espace(_ isRequired: Bool, parameterMissing parameter: String) throws -> Bool {
            if isRequired { throw OSFANLError.missing(parameter) }
            return false // indicates that there's no value associated to `parameter`
        }
        
        guard let eventData, !eventData.isEmpty else { return try espace(isRequired, parameterMissing: "eventParameters") }
        let parameter = dataField.rawValue
        guard let parameterValue = eventData[parameter] else { return try espace(isRequired, parameterMissing: parameter) }

        let dataField: (type: StringConvertable.Type, value: StringConvertable?) = dataField.isDecimalType ? (Decimal.self, parameterValue as? Decimal) : (String.self, parameterValue as? String)
        if dataField.value == nil { throw OSFANLError.invalidType(parameter, type: dataField.type.variableType) }
        return true // indicates that there's a value associated to `parameter`
    }
}
