function Pandoc(doc)
    if doc.meta and doc.meta.references then
        for _, ref in ipairs(doc.meta.references) do
            ref['publisher'] = nil
            ref['publisher-place'] = nil
            ref['address'] = nil
        end
    end
    return doc
end