codeunit 58502 "Replace LIT Trans.LineByRecipe"
{
    var
        RecipeExplosionMgmt: Codeunit "Recipe Explosion Management";
        UOMMgt: Codeunit "Unit of Measure Management";

    [EventSubscriber(
        ObjectType::Table,
        Database::"LIT TransferDoc Line",
        'OnBeforeExplodeTransferBOM',
        '', true, true)]
    local procedure UseRecipeInsteadOfTransferBOM(
        var TransferLine: Record "LIT TransferDoc Line";
        var NewLineNo: Integer;
        var IsHandled: Boolean)
    var
        RecipeMgmtSetup: Record "Recipe Management Setup";
        Location: Record Location;
        RecipeHeader: Record "Recipe Header";
        Item: Record Item;
        ItemQtyBaseMap: Dictionary of [Code[20], Decimal];
        ItemNo: Code[20];
        QtyBase: Decimal;
        VisitedRecipes: List of [Code[20]];
        RecipeNo: Code[20];
    begin
        if TransferLine."LIT Parent Item" <> '' then exit;
        if TransferLine."LIT Quantity" = 0 then exit;
        if not RecipeMgmtSetup.Get() then exit;
        if not RecipeMgmtSetup."Overwrite Assembly BOMs" then exit;
        if not Location.Get(TransferLine."LIT Transfer-from Code") then exit;
        if not Location."Overwrite Assembly BOMs" then exit;
        if not Item.Get(TransferLine."LIT Item No.") then
            exit;

        if (Item."Replenishment System" in
            [Item."Replenishment System"::Assembly,
             Item."Replenishment System"::"Prod. Order"]) then begin

            if not Item."Overwrite Assembly BOMs" then exit;
        end;

        RecipeNo :=
            RecipeExplosionMgmt.FindRecipeForItem(
                TransferLine."LIT Transfer-from Code",
                TransferLine."LIT Item No.");

        if RecipeNo = '' then exit;

        RecipeHeader.Get(RecipeNo);

        IsHandled := true;

        DeleteRecipeGeneratedLines(TransferLine);

        Clear(VisitedRecipes);
        VisitedRecipes.Add(RecipeHeader."Recipe No.");
        Clear(ItemQtyBaseMap);

        Item.Get(TransferLine."LIT Item No.");

        RecipeExplosionMgmt.ExplodeRecipeLines(
            TransferLine."LIT Transfer-from Code",
            RecipeHeader,
            TransferLine."LIT Quantity" *
            UOMMgt.GetQtyPerUnitOfMeasure(Item, TransferLine."LIT UOM"),
            VisitedRecipes,
            ItemQtyBaseMap);

        foreach ItemNo in ItemQtyBaseMap.Keys do begin
            ItemQtyBaseMap.Get(ItemNo, QtyBase);
            InsertTransferLine(TransferLine, ItemNo, QtyBase, NewLineNo);
        end;
    end;

    local procedure InsertTransferLine(
        ParentLine: Record "LIT TransferDoc Line";
        ItemNo: Code[20];
        QtyBase: Decimal;
        var LineNo: Integer)
    var
        LITTransferDocLine: Record "LIT TransferDoc Line";
        Item: Record Item;
    begin
        Item.Get(ItemNo);

        LineNo += 10000;

        LITTransferDocLine.Init();
        LITTransferDocLine.Validate("LIT TransferDoc No.", ParentLine."LIT TransferDoc No.");
        LITTransferDocLine.Validate("LIT TransferDoc Line No.", LineNo);
        LITTransferDocLine.Validate("LIT Parent Item", ParentLine."LIT Item No.");
        LITTransferDocLine.Validate("LIT Parent Line No.", ParentLine."LIT TransferDoc Line No.");
        LITTransferDocLine.Validate("LIT Item No.", ItemNo);
        LITTransferDocLine.Validate("LIT UOM", Item."Base Unit of Measure");
        LITTransferDocLine.Validate("LIT Raw Meterial", true);
        LITTransferDocLine.Validate("LIT Quantity",
            QtyBase / UOMMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure"));
        LITTransferDocLine.Insert(true);
    end;

    local procedure DeleteRecipeGeneratedLines(
        ParentLine: Record "LIT TransferDoc Line")
    var
        LITTransferDocLine: Record "LIT TransferDoc Line";
    begin
        LITTransferDocLine.SetRange("LIT TransferDoc No.", ParentLine."LIT TransferDoc No.");
        LITTransferDocLine.SetRange("LIT Parent Item", ParentLine."LIT Item No.");
        LITTransferDocLine.DeleteAll();
    end;
}
