// pageextension 58500 "Location Card Page Ext" extends "Location Card"
// {
//     layout
//     {
//         addafter("Overwrite Assembly BOMs")
//         {
//             field("Buy-from Vendor No."; Rec."Buy-from Vendor No.")
//             {
//                 ApplicationArea = All;
//                 Caption = 'Vendor No.';
//                 ToolTip = 'Specifies the name of the vendor who delivers the products.';
//             }
//             field("Sell-to Customer No."; Rec."Sell-to Customer No.")
//             {
//                 ApplicationArea = All;
//                 Caption = 'Customer No.';
//                 ToolTip = 'Specifies the name of the customer who will receive the products and be billed by default.';
//             }
//         }
//     }
// }