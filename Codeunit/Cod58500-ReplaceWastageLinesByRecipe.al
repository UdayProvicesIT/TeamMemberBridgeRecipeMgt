codeunit 58500 "Replace Wastage LinesByRecipe"
{
    var
        RecipeExplosionMgmt: Codeunit "Recipe Explosion Management";
        UOMMgt: Codeunit "Unit of Measure Management";

    [EventSubscriber(
        ObjectType::Table,
        Database::"LIT ItemJrnlDoc Line",
        'OnBeforeExplodeAssemblyBOM',
        '', true, true)]
    local procedure UseRecipeInsteadOfWastageBOM(
        var ParentLine: Record "LIT ItemJrnlDoc Line";
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
        if ParentLine."LIT Parent Item" <> '' then exit;
        if ParentLine."LIT Quantity" = 0 then exit;
        if not RecipeMgmtSetup.Get() then exit;
        if not RecipeMgmtSetup."Overwrite Assembly BOMs" then exit;
        if not Location.Get(ParentLine."LIT Location Code") then exit;
        if not Location."Overwrite Assembly BOMs" then exit;
        if not Item.Get(ParentLine."LIT Item No.") then
            exit;

        if (Item."Replenishment System" in
            [Item."Replenishment System"::Assembly,
             Item."Replenishment System"::"Prod. Order"]) then begin

            if not Item."Overwrite Assembly BOMs" then exit;
        end;

        RecipeNo :=
            RecipeExplosionMgmt.FindRecipeForItem(
                ParentLine."LIT Location Code",
                ParentLine."LIT Item No.");

        if RecipeNo = '' then exit;

        RecipeHeader.Get(RecipeNo);

        IsHandled := true;

        DeleteRecipeGeneratedLines(ParentLine);

        Clear(VisitedRecipes);
        VisitedRecipes.Add(RecipeHeader."Recipe No.");
        Clear(ItemQtyBaseMap);

        Item.Get(ParentLine."LIT Item No.");

        RecipeExplosionMgmt.ExplodeRecipeLines(
            ParentLine."LIT Location Code",
            RecipeHeader,
            ParentLine."LIT Quantity" *
            UOMMgt.GetQtyPerUnitOfMeasure(Item, ParentLine."LIT Unit of Measure Code"),
            VisitedRecipes,
            ItemQtyBaseMap);

        foreach ItemNo in ItemQtyBaseMap.Keys do begin
            ItemQtyBaseMap.Get(ItemNo, QtyBase);
            InsertWastageLine(ParentLine, ItemNo, QtyBase, NewLineNo);
        end;
    end;

    local procedure InsertWastageLine(
        ParentLine: Record "LIT ItemJrnlDoc Line";
        ItemNo: Code[20];
        QtyBase: Decimal;
        var LineNo: Integer)
    var
        LITItemJrnlDocLine: Record "LIT ItemJrnlDoc Line";
        Item: Record Item;
    begin
        Item.Get(ItemNo);

        LineNo += 10000;

        LITItemJrnlDocLine.Init();
        LITItemJrnlDocLine.Validate("LIT ItemJrnlDoc No.", ParentLine."LIT ItemJrnlDoc No.");
        LITItemJrnlDocLine.Validate("LIT ItemJrnlDoc Line No.", LineNo);
        LITItemJrnlDocLine.Validate("LIT Parent Item", ParentLine."LIT Item No.");
        LITItemJrnlDocLine.Validate("LIT Parent Line No.", ParentLine."LIT ItemJrnlDoc Line No.");
        LITItemJrnlDocLine.Validate("LIT Item No.", ItemNo);
        LITItemJrnlDocLine.Validate("LIT Unit of Measure Code", Item."Base Unit of Measure");
        LITItemJrnlDocLine.Validate("LIT Raw Material", true);
        LITItemJrnlDocLine.Validate("LIT Quantity",
            QtyBase / UOMMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure"));
        LITItemJrnlDocLine.Insert(true);
    end;

    local procedure DeleteRecipeGeneratedLines(
        ParentLine: Record "LIT ItemJrnlDoc Line")
    var
        LITItemJrnlDocLine: Record "LIT ItemJrnlDoc Line";
    begin
        LITItemJrnlDocLine.SetRange("LIT ItemJrnlDoc No.", ParentLine."LIT ItemJrnlDoc No.");
        LITItemJrnlDocLine.SetRange("LIT Parent Item", ParentLine."LIT Item No.");
        LITItemJrnlDocLine.DeleteAll();
    end;
}
