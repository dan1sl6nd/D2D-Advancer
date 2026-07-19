function cleanedValue(value) {
    if (value === null || value === undefined) {
        return null;
    }
    const text = String(value).trim();
    return text.length > 0 ? text : null;
}

function safeArray(getter) {
    try {
        return getter() || [];
    } catch (_) {
        return [];
    }
}

function normalizedSearchText(value) {
    if (!value) {
        return "";
    }
    return String(value)
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .trim();
}

function matchedService(fields) {
    const searchable = fields.map(normalizedSearchText).join(" | ");
    const services = ["window cleaning", "gutter cleaning"];
    let bestMatch = null;

    services.forEach(function (service) {
        const index = searchable.indexOf(service);
        if (index >= 0 && (bestMatch === null || index < bestMatch.index)) {
            bestMatch = { service: service, index: index };
        }
    });

    return bestMatch ? bestMatch.service : null;
}

function extractedPrice(note) {
    if (!note) {
        return null;
    }

    const patterns = [
        /\b(?:price|quote(?:d)?|estimate(?:d)?|value)\b\s*(?:is\s*)?(?:[:=\-]\s*)?(?:(?:cad|ca)\s*)?(?:\$\s*)?([0-9]+(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?)/i,
        /(?:(?:cad|ca)\s*)?\$\s*([0-9]+(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?)/i,
        /^\s*(?:(?:cad|ca)\s*)?\$?\s*([0-9]+(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:cad)?\s*$/i
    ];

    for (let index = 0; index < patterns.length; index += 1) {
        const match = String(note).match(patterns[index]);
        if (!match) {
            continue;
        }
        const amount = Number(match[1].replace(/[, ]/g, ""));
        if (Number.isFinite(amount) && amount > 0 && amount <= 10000000) {
            return amount;
        }
    }

    return null;
}

function nestedValues(values, index) {
    return Array.isArray(values[index]) ? values[index] : [];
}

function labeledValues(labelsByPerson, valuesByPerson, personIndex) {
    const labels = nestedValues(labelsByPerson, personIndex);
    const values = nestedValues(valuesByPerson, personIndex);
    const results = [];

    for (let index = 0; index < values.length; index += 1) {
        const value = cleanedValue(values[index]);
        if (!value) {
            continue;
        }
        results.push({
            label: cleanedValue(labels[index]),
            value: value
        });
    }
    return results;
}

function postalAddresses(addressFields, personIndex) {
    const fields = {};
    Object.keys(addressFields).forEach(function (key) {
        fields[key] = nestedValues(addressFields[key], personIndex);
    });
    const addressCount = Math.max(
        fields.formatted.length,
        fields.street.length,
        fields.city.length,
        fields.state.length,
        fields.postalCode.length,
        fields.country.length
    );
    const results = [];

    for (let index = 0; index < addressCount; index += 1) {
        const address = {
            label: cleanedValue(fields.label[index]),
            formatted: cleanedValue(fields.formatted[index]),
            street: cleanedValue(fields.street[index]),
            city: cleanedValue(fields.city[index]),
            state: cleanedValue(fields.state[index]),
            postalCode: cleanedValue(fields.postalCode[index]),
            country: cleanedValue(fields.country[index]),
            countryCode: cleanedValue(fields.countryCode[index])
        };
        if (address.formatted !== null || address.street !== null) {
            results.push(address);
        }
    }
    return results;
}

function run() {
    const contacts = Application("Contacts");
    const people = contacts.people;
    const identifiers = safeArray(function () { return people.id(); });
    const names = safeArray(function () { return people.name(); });
    const firstNames = safeArray(function () { return people.firstName(); });
    const middleNames = safeArray(function () { return people.middleName(); });
    const lastNames = safeArray(function () { return people.lastName(); });
    const nicknames = safeArray(function () { return people.nickname(); });
    const organizations = safeArray(function () { return people.organization(); });
    const departments = safeArray(function () { return people.department(); });
    const jobTitles = safeArray(function () { return people.jobTitle(); });
    const notes = safeArray(function () { return people.note(); });
    const matchedRecords = [];

    for (let index = 0; index < identifiers.length; index += 1) {
        const record = {
            identifier: cleanedValue(identifiers[index]),
            name: cleanedValue(names[index]),
            firstName: cleanedValue(firstNames[index]),
            middleName: cleanedValue(middleNames[index]),
            lastName: cleanedValue(lastNames[index]),
            nickname: cleanedValue(nicknames[index]),
            organization: cleanedValue(organizations[index]),
            department: cleanedValue(departments[index]),
            jobTitle: cleanedValue(jobTitles[index]),
            note: cleanedValue(notes[index]),
            price: null,
            phoneNumbers: [],
            emailAddresses: [],
            postalAddresses: []
        };

        if (!record.identifier) {
            continue;
        }

        const service = matchedService([
            record.name,
            record.nickname,
            record.organization,
            record.department,
            record.jobTitle,
            record.note
        ]);
        if (!service) {
            continue;
        }

        record.price = extractedPrice(record.note);
        matchedRecords.push({ personIndex: index, record: record });
    }

    const phoneLabels = safeArray(function () { return people.phones.label(); });
    const phoneValues = safeArray(function () { return people.phones.value(); });
    const emailLabels = safeArray(function () { return people.emails.label(); });
    const emailValues = safeArray(function () { return people.emails.value(); });
    const addressFields = {
        label: safeArray(function () { return people.addresses.label(); }),
        formatted: safeArray(function () { return people.addresses.formattedAddress(); }),
        street: safeArray(function () { return people.addresses.street(); }),
        city: safeArray(function () { return people.addresses.city(); }),
        state: safeArray(function () { return people.addresses.state(); }),
        postalCode: safeArray(function () { return people.addresses.zip(); }),
        country: safeArray(function () { return people.addresses.country(); }),
        countryCode: safeArray(function () { return people.addresses.countryCode(); })
    };
    const exportedContacts = [];

    matchedRecords.forEach(function (matchedRecord) {
        const index = matchedRecord.personIndex;
        const record = matchedRecord.record;
        record.phoneNumbers = labeledValues(phoneLabels, phoneValues, index);
        record.emailAddresses = labeledValues(emailLabels, emailValues, index);
        record.postalAddresses = postalAddresses(addressFields, index);
        exportedContacts.push(record);
    });

    return JSON.stringify({
        schemaVersion: 1,
        exportedAt: new Date().toISOString(),
        source: "macOS Contacts",
        contacts: exportedContacts
    }, null, 2);
}
