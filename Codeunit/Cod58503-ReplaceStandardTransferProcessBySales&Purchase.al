// codeunit 58503 "LIT Commercial Transfer Bridge"
// {
//     Subtype = Normal;

//     [EventSubscriber(ObjectType::Codeunit, Codeunit::"LIT Process Transfer Order",
//                      'OnBeforeProcessLITTransfer', '', false, false)]
//     local procedure HandleCommercialTransfer(var LITHeader: Record "LIT TransferDoc Header"; var IsHandled: Boolean)
//     var
//         FromLocation: Record Location;
//         ToLocation: Record Location;
//     begin
//         // Load both locations
//         FromLocation.Get(LITHeader."LIT Transfer-from Code");
//         ToLocation.Get(LITHeader."LIT Transfer-to Code");

//         FromLocation.CalcFields("Business Group");
//         ToLocation.CalcFields("Business Group");

//         // If Business Groups are same, allow normal Transfer Order
//         if FromLocation."Business Group" = ToLocation."Business Group" then
//             exit;

//         // Otherwise this is a commercial transaction
//         CreateCommercialDocs(LITHeader, FromLocation, ToLocation);

//         // Stop Transfer Order creation
//         IsHandled := true;
//     end;

//     local procedure CreateCommercialDocs(
//      var LITTransferDocHeader: Record "LIT TransferDoc Header";
//      FromLocation: Record Location;
//      ToLocation: Record Location)
//     begin
//         FromLocation.TestField("Buy-from Vendor No.");
//         ToLocation.TestField("Sell-to Customer No.");

//         CreateAndPostSalesInvoice(LITTransferDocHeader, FromLocation, ToLocation);
//         CreateAndPostPurchaseInvoice(LITTransferDocHeader, FromLocation, ToLocation);

//         PostTransferDocument(LITTransferDocHeader);
//     end;


//     // Sales Invoice (From Location sells to To Location)
//     local procedure CreateAndPostSalesInvoice(LITTransferDocHeader: Record "LIT TransferDoc Header"; FromLocation: Record Location; ToLocation: Record Location): Code[20]
//     var
//         SalesHeader: Record "Sales Header";
//         SalesLine: Record "Sales Line";
//         LITTransferDocLine: Record "LIT TransferDoc Line";
//         Item: Record Item;
//         SalesPost: Codeunit "Sales-Post";
//     begin
//         SalesHeader.Init();
//         SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
//         SalesHeader.Insert(true);

//         SalesHeader.Validate("Sell-to Customer No.", ToLocation."Sell-to Customer No.");
//         SalesHeader.Validate("Location Code", FromLocation.Code);

//         SalesHeader.Validate("Document Date", LITTransferDocHeader."LIT Posting Date");
//         SalesHeader.Validate("Posting Date", LITTransferDocHeader."LIT Posting Date");
//         SalesHeader.Validate("Order Date", LITTransferDocHeader."LIT Posting Date");
//         SalesHeader.Validate("Due Date", LITTransferDocHeader."LIT Posting Date");

//         SalesHeader.Validate("External Document No.", LITTransferDocHeader."LIT No.");
//         SalesHeader.Modify(true);

//         // Lines
//         LITTransferDocLine.SetRange("LIT TransferDoc No.", LITTransferDocHeader."LIT No.");
//         if LITTransferDocLine.FindSet() then
//             repeat
//                 SalesLine.Init();
//                 SalesLine."Document Type" := SalesHeader."Document Type";
//                 SalesLine."Document No." := SalesHeader."No.";

//                 SalesLine."Line No." := GetNextSalesLineNo(SalesHeader);

//                 SalesLine.Validate(Type, SalesLine.Type::Item);
//                 SalesLine.Validate("No.", LITTransferDocLine."LIT Item No.");
//                 SalesLine.Validate(Quantity, LITTransferDocLine."LIT Quantity");
//                 if Item.Get(LITTransferDocLine."LIT Item No.") then
//                     SalesLine.Validate("Unit Price", Item."Unit Cost");

//                 SalesLine.Insert(true);
//             until LITTransferDocLine.Next() = 0;

//         SalesHeader.Validate(Ship, true);
//         SalesHeader.Validate(Invoice, true);
//         SalesHeader.Modify(true);

//         // Auto-post order
//         SalesPost.Run(SalesHeader);

//     end;

//     local procedure GetNextSalesLineNo(SalesHeader: Record "Sales Header"): Integer
//     var
//         SalesLine: Record "Sales Line";
//     begin
//         SalesLine.SetRange("Document Type", SalesHeader."Document Type");
//         SalesLine.SetRange("Document No.", SalesHeader."No.");

//         if SalesLine.FindLast() then
//             exit(SalesLine."Line No." + 10000)
//         else
//             exit(10000);
//     end;


//     // Purchase Invoice (To Location buys from From Location)
//     local procedure CreateAndPostPurchaseInvoice(LITTransferDocHeader: Record "LIT TransferDoc Header"; FromLocation: Record Location; ToLocation: Record Location): Code[20]
//     var
//         PurchaseHeader: Record "Purchase Header";
//         PurchaseLine: Record "Purchase Line";
//         LITTransferDocLine: Record "LIT TransferDoc Line";
//         PurchPost: Codeunit "Purch.-Post";
//         TempDimSetEntry: Record "Dimension Set Entry" temporary;
//         DimMgt: Codeunit DimensionManagement;
//         DimSetID: Integer;
//     begin
//         PurchaseHeader.Init();
//         PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::Order;
//         PurchaseHeader.Insert(true);

//         PurchaseHeader.Validate("Buy-from Vendor No.", FromLocation."Buy-from Vendor No.");

//         PurchaseHeader.Validate("Document Date", LITTransferDocHeader."LIT Posting Date");
//         PurchaseHeader.Validate("Posting Date", LITTransferDocHeader."LIT Posting Date");
//         PurchaseHeader.Validate("Order Date", LITTransferDocHeader."LIT Posting Date");
//         PurchaseHeader.Validate("Due Date", LITTransferDocHeader."LIT Posting Date");

//         PurchaseHeader.Validate("Vendor Invoice No.", LITTransferDocHeader."LIT No.");

//         // Vendor default dimensions
//         CollectDefaultDims(Database::Vendor, PurchaseHeader."Buy-from Vendor No.", TempDimSetEntry);

//         // Location default dimensions
//         CollectDefaultDims(Database::Location, ToLocation.Code, TempDimSetEntry);

//         // Create ONE Dimension Set ID
//         DimSetID := DimMgt.GetDimensionSetID(TempDimSetEntry);

//         if DimSetID = 0 then
//             Error('Purchase Header Dimension Set ID is 0.');

//         PurchaseHeader.Validate("Dimension Set ID", DimSetID);
//         PurchaseHeader.Modify(true);

//         // Lines
//         LITTransferDocLine.SetRange("LIT TransferDoc No.", LITTransferDocHeader."LIT No.");
//         if LITTransferDocLine.FindSet() then
//             repeat
//                 PurchaseLine.Init();
//                 PurchaseLine."Document Type" := PurchaseHeader."Document Type";
//                 PurchaseLine."Document No." := PurchaseHeader."No.";

//                 PurchaseLine."Line No." := GetNextPurchaseLineNo(PurchaseHeader);

//                 PurchaseLine.Validate(Type, PurchaseLine.Type::Item);
//                 PurchaseLine.Validate("No.", LITTransferDocLine."LIT Item No.");
//                 PurchaseLine.Validate(Quantity, LITTransferDocLine."LIT Quantity");
//                 PurchaseLine.Validate("Location Code", ToLocation.Code);

//                 PurchaseLine.Insert(true);
//             until LITTransferDocLine.Next() = 0;

//         PurchaseHeader.Validate(Receive, true);
//         PurchaseHeader.Validate(Invoice, true);
//         PurchaseHeader.Modify(true);

//         PurchPost.Run(PurchaseHeader);
//     end;

//     local procedure GetNextPurchaseLineNo(PurchaseHeader: Record "Purchase Header"): Integer
//     var
//         PurchaseLine: Record "Purchase Line";
//     begin
//         PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
//         PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");

//         if PurchaseLine.FindLast() then
//             exit(PurchaseLine."Line No." + 10000)
//         else
//             exit(10000);
//     end;

//     local procedure CollectDefaultDims(
//      TableID: Integer;
//      No: Code[20];
//      var TempDimSetEntry: Record "Dimension Set Entry" temporary)
//     var
//         DefaultDim: Record "Default Dimension";
//     begin
//         DefaultDim.SetRange("Table ID", TableID);
//         DefaultDim.SetRange("No.", No);

//         if DefaultDim.FindSet() then
//             repeat
//                 TempDimSetEntry.Init();
//                 TempDimSetEntry.Validate("Dimension Code", DefaultDim."Dimension Code");
//                 TempDimSetEntry.Validate("Dimension Value Code", DefaultDim."Dimension Value Code");
//                 TempDimSetEntry.Insert();
//             until DefaultDim.Next() = 0;
//     end;

//     local procedure PostTransferDocument(
//          var LITTransferDocHeader: Record "LIT TransferDoc Header")
//     var
//         LITTransferDocLine: Record "LIT TransferDoc Line";
//     begin
//         LITTransferDocHeader."LIT Status" := LITTransferDocHeader."LIT Status"::Posted;
//         LITTransferDocHeader.Modify(false);

//         LITTransferDocLine.Reset();
//         LITTransferDocLine.SetRange("LIT TransferDoc No.", LITTransferDocHeader."LIT No.");
//         if LITTransferDocLine.FindSet(true) then
//             repeat
//                 LITTransferDocLine."LIT Status" := LITTransferDocLine."LIT Status"::Posted;
//                 LITTransferDocLine.Modify(false);
//             until LITTransferDocLine.Next() = 0;
//     end;
// }
