= Invoice
#import "data.typ": record
#import "@preview/cetz:0.3.4": canvas

*#record.name* owes #sys.inputs.at("amount", default: undefined_variable)
