import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { SignJWT, importPKCS8 } from "jose";

const ROOT = process.cwd();
const BUNDLE_ID = "dan1sland.D2D-Advancer";
const VERSION = "1.3";
const BUILD_NUMBER = "3";
const LOCALE = "en-US";
const IPHONE_SCREENSHOT_DISPLAY_TYPE = "APP_IPHONE_67";
const IPAD_SCREENSHOT_DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129";
const IPHONE_SCREENSHOT_SIZES = new Set([
  "1260x2736",
  "1290x2796",
  "1320x2868",
]);
const IPAD_SCREENSHOT_SIZES = new Set(["2048x2732", "2064x2752"]);

const URLS = {
  marketing: "https://dan1sl6nd.github.io/D2D-Advancer/",
  privacy: "https://dan1sl6nd.github.io/D2D-Advancer/PRIVACY_POLICY.html",
  support: "https://dan1sl6nd.github.io/D2D-Advancer/SUPPORT.html",
};

const LISTING = {
  subtitle: "Field Sales & Team CRM",
  promotionalText:
    "Plan territories, manage leads and follow-ups, schedule jobs, and coordinate a small field team from one focused workspace.",
  keywords:
    "door to door,sales,leads,crm,field service,territory,appointments,follow up,team",
  description: `D2D Advancer is a field-sales and service workflow for door-to-door professionals and small crews.

MAP AND CAPTURE FIELD WORK
• Add leads from the map or lead list.
• See clustered leads, status, priority, and names for sold or interested work.
• Filter the map for hot, due, today, sold, and upcoming leads.
• Open directions and Street View when available.

STAY ON TOP OF EVERY LEAD
• Record contact details, notes, photos, voice notes, quotes, and follow-up dates.
• Use clear statuses and priorities to focus the day.
• Create appointments and service arrival windows.
• Edit or delete leads, follow-ups, and appointments when plans change.

PRIVATE SOLO WORKSPACE
Personal leads remain private to the user. Data is stored on the device and can sync through the Apple ID already on the device with iCloud.

TEAM WORKSPACE
The Team plan includes one owner and two worker seats for sales reps or technicians.
• Assign leads and sold jobs to the right worker.
• Workers see only the Team work assigned to them and Team leads they create.
• Send important status updates and owner alerts.
• Share live location only after a member manually goes On duty.
• Review active-hours routes for up to 30 days.

SUBSCRIPTIONS
Solo Monthly and Solo Yearly unlock the private field workflow. Team Monthly and Team Yearly include Solo features plus the three-seat Team workspace. Prices are shown by Apple before purchase. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel subscriptions in Apple ID settings.

Privacy: ${URLS.privacy}
Terms: https://dan1sl6nd.github.io/D2D-Advancer/TERMS_OF_USE.html`,
  whatsNew: `Version 1.3 adds Team Workspace and streamlines the field workflow.

• New Solo Monthly, Solo Yearly, Team Monthly, and Team Yearly options.
• Assign Team leads and sold jobs to sales reps or technicians.
• Add service arrival windows and job details for technicians.
• Manual On duty and Off duty location sharing with 30-day route retention.
• Owner alerts for interested, booked, converted, and high-priority Team work.
• Faster map loading, improved clustering, lead names for sold and interested work, and more reliable filters.
• Simplified lead, follow-up, appointment, and More screens.
• In-app Team leave, close, account deletion, and legacy subscription continuity.

Existing personal leads remain private and are not automatically moved into Team.`,
};

const REVIEW_NOTES = `D2D Advancer is a field-sales CRM with separate personal and Team workspaces.

REVIEW PATH
1. Complete onboarding and select the personal workspace.
2. Add a lead from the Map or Leads tab, edit its details, set a follow-up, and create an appointment.
3. Open More > Subscription to review Solo and Team offers. Purchases and restore use StoreKit.
4. Open More > Account Management to verify the in-app account deletion path.

TEAM REVIEW
No pre-created demo account is required. Sign in with Apple creates the app's Firebase Team identity without a separate Firebase login. Purchase a Team plan in Apple's sandbox, open More > Team Workspace, create an owner workspace, and generate a single-use worker invite. A second reviewer identity can join as a sales rep or technician.

Personal leads remain private in local/iCloud storage. Team identity, assigned Team leads and jobs, owner alerts, and Team entitlement state use Firebase. Workers see only assigned Team records and Team leads they create. Location sharing starts only after manually selecting On duty and stops after Off duty. The app does not request Always Location permission.

The Team plan includes one owner and two worker seats. When Team access expires, Team edits pause, records remain readable for seven days, and shared Team access then pauses until renewal.`;

const AGE_RATING = {
  advertising: false,
  ageAssurance: false,
  alcoholTobaccoOrDrugUseOrReferences: "NONE",
  contests: "NONE",
  gambling: false,
  gamblingSimulated: "NONE",
  gunsOrOtherWeapons: "NONE",
  healthOrWellnessTopics: false,
  horrorOrFearThemes: "NONE",
  lootBox: false,
  matureOrSuggestiveThemes: "NONE",
  medicalOrTreatmentInformation: "NONE",
  messagingAndChat: false,
  parentalControls: false,
  profanityOrCrudeHumor: "NONE",
  sexualContentGraphicAndNudity: "NONE",
  sexualContentOrNudity: "NONE",
  unrestrictedWebAccess: false,
  userGeneratedContent: false,
  violenceCartoonOrFantasy: "NONE",
  violenceRealistic: "NONE",
  violenceRealisticProlongedGraphicOrSadistic: "NONE",
  ageRatingOverrideV2: "NONE",
  developerAgeRatingInfoUrl: URLS.support,
};

function loadEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const match = line.trim().match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match || process.env[match[1]]) continue;
    process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, "");
  }
}

function argumentValue(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : null;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function validateMetadata() {
  const limits = [
    ["subtitle", LISTING.subtitle, 30],
    ["promotionalText", LISTING.promotionalText, 170],
    ["keywords", LISTING.keywords, 100],
    ["description", LISTING.description, 4000],
    ["whatsNew", LISTING.whatsNew, 4000],
  ];
  for (const [name, value, maximum] of limits) {
    if (!value || value.length > maximum) {
      throw new Error(`${name} length ${value?.length ?? 0} exceeds ${maximum}`);
    }
  }
}

async function getToken() {
  const keyId = process.env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID;
  const keyPath = process.env.ASC_KEY_PATH;
  if (!keyId || !issuerId || !keyPath) {
    throw new Error("Missing ASC_KEY_ID, ASC_ISSUER_ID, or ASC_KEY_PATH");
  }

  const privateKey = await importPKCS8(fs.readFileSync(keyPath, "utf8"), "ES256");
  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId, typ: "JWT" })
    .setIssuer(issuerId)
    .setAudience("appstoreconnect-v1")
    .setIssuedAt(now)
    .setExpirationTime(now + 1200)
    .sign(privateKey);
}

async function ascFetch(token, route, options = {}, attempt = 0) {
  const method = options.method ?? "GET";
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1${route}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const responseText = await response.text();
  if (!response.ok) {
    const retryable =
      (response.status === 429 || response.status >= 500) && attempt < 5;
    if (retryable) {
      await sleep(750 * 2 ** attempt);
      return ascFetch(token, route, options, attempt + 1);
    }
    throw new Error(`ASC API ${response.status} for ${route}: ${responseText}`);
  }
  return responseText ? JSON.parse(responseText) : {};
}

async function optionalFetch(token, route) {
  try {
    return await ascFetch(token, route);
  } catch (error) {
    if (/ASC API 404/.test(error.message)) return null;
    throw error;
  }
}

function nextRoute(link) {
  if (!link) return null;
  const url = new URL(link);
  return `${url.pathname.replace(/^\/v1/, "")}${url.search}`;
}

async function listAll(token, route) {
  const data = [];
  let next = route;
  while (next) {
    const response = await ascFetch(token, next);
    data.push(...(response.data ?? []));
    next = nextRoute(response.links?.next);
  }
  return data;
}

async function findApp(token) {
  const response = await ascFetch(
    token,
    `/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name,bundleId,sku,primaryLocale,subscriptionStatusUrl,subscriptionStatusUrlVersion,subscriptionStatusUrlForSandbox,subscriptionStatusUrlVersionForSandbox`
  );
  const app = response.data?.[0];
  if (!app) throw new Error(`No App Store Connect app found for ${BUNDLE_ID}`);
  return app;
}

async function listVersions(token, appId) {
  return listAll(
    token,
    `/apps/${appId}/appStoreVersions?filter[platform]=IOS&fields[appStoreVersions]=versionString,appStoreState,platform,copyright,releaseType,earliestReleaseDate&limit=200`
  );
}

async function ensureVersion(token, appId) {
  const versions = await listVersions(token, appId);
  const existing = versions.find(
    (version) => version.attributes?.versionString === VERSION
  );
  if (existing) return existing;

  return (
    await ascFetch(token, "/appStoreVersions", {
      method: "POST",
      body: {
        data: {
          type: "appStoreVersions",
          attributes: {
            platform: "IOS",
            versionString: VERSION,
            releaseType: "MANUAL",
            copyright: "2026 D2D Advancer",
          },
          relationships: {
            app: { data: { type: "apps", id: appId } },
          },
        },
      },
    })
  ).data;
}

async function patchVersion(token, versionId) {
  return (
    await ascFetch(token, `/appStoreVersions/${versionId}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appStoreVersions",
          id: versionId,
          attributes: {
            releaseType: "MANUAL",
            copyright: "2026 D2D Advancer",
          },
        },
      },
    })
  ).data;
}

async function ensureVersionLocalization(token, versionId) {
  const localizations = await listAll(
    token,
    `/appStoreVersions/${versionId}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,description,keywords,marketingUrl,promotionalText,supportUrl,whatsNew&limit=200`
  );
  const existing = localizations.find(
    (localization) => localization.attributes?.locale === LOCALE
  );
  if (existing) return existing;

  return (
    await ascFetch(token, "/appStoreVersionLocalizations", {
      method: "POST",
      body: {
        data: {
          type: "appStoreVersionLocalizations",
          attributes: { locale: LOCALE },
          relationships: {
            appStoreVersion: {
              data: { type: "appStoreVersions", id: versionId },
            },
          },
        },
      },
    })
  ).data;
}

async function applyVersionLocalization(token, versionId) {
  const localization = await ensureVersionLocalization(token, versionId);
  return (
    await ascFetch(token, `/appStoreVersionLocalizations/${localization.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appStoreVersionLocalizations",
          id: localization.id,
          attributes: {
            description: LISTING.description,
            keywords: LISTING.keywords,
            marketingUrl: URLS.marketing,
            promotionalText: LISTING.promotionalText,
            supportUrl: URLS.support,
            whatsNew: LISTING.whatsNew,
          },
        },
      },
    })
  ).data;
}

async function readScreenshotSets(token, localizationId) {
  const sets = await listAll(
    token,
    `/appStoreVersionLocalizations/${localizationId}/appScreenshotSets?fields[appScreenshotSets]=screenshotDisplayType,appScreenshots&limit=200`
  );
  const summaries = [];
  for (const set of sets) {
    const screenshots = await listAll(
      token,
      `/appScreenshotSets/${set.id}/appScreenshots?fields[appScreenshots]=fileName,fileSize,sourceFileChecksum,imageAsset,assetDeliveryState&limit=200`
    );
    summaries.push({
      id: set.id,
      screenshotDisplayType: set.attributes?.screenshotDisplayType,
      screenshots: screenshots.map((screenshot) => ({
        id: screenshot.id,
        ...screenshot.attributes,
      })),
    });
  }
  return summaries;
}

function screenshotFilesInDirectory(directoryPath) {
  if (!fs.existsSync(directoryPath)) {
    throw new Error(`Screenshot directory does not exist: ${directoryPath}`);
  }
  const files = fs
    .readdirSync(directoryPath)
    .filter((name) => /\.(png|jpe?g)$/i.test(name))
    .sort((left, right) => left.localeCompare(right, "en"))
    .map((name) => path.join(directoryPath, name));
  if (files.length < 1 || files.length > 10) {
    throw new Error(
      `Expected 1-10 screenshots in ${directoryPath}; found ${files.length}`
    );
  }
  return files;
}

function pngDimensions(filePath) {
  const file = fs.readFileSync(filePath);
  const signature = "89504e470d0a1a0a";
  if (file.length < 24 || file.subarray(0, 8).toString("hex") !== signature) {
    throw new Error(`Only PNG release screenshots are supported: ${filePath}`);
  }
  return {
    width: file.readUInt32BE(16),
    height: file.readUInt32BE(20),
  };
}

function validatedScreenshotFiles(
  directoryPath,
  supportedSizes,
  sizeDescription
) {
  return screenshotFilesInDirectory(directoryPath).map((filePath) => {
    const { width, height } = pngDimensions(filePath);
    if (!supportedSizes.has(`${width}x${height}`)) {
      throw new Error(
        `${path.basename(filePath)} is ${width}x${height}; expected ${sizeDescription}`
      );
    }
    return {
      filePath,
      fileName: path.basename(filePath),
      fileSize: fs.statSync(filePath).size,
      sourceFileChecksum: crypto
        .createHash("md5")
        .update(fs.readFileSync(filePath))
        .digest("hex"),
    };
  });
}

async function createAppScreenshot(token, screenshotSetId, screenshot) {
  return (
    await ascFetch(token, "/appScreenshots", {
      method: "POST",
      body: {
        data: {
          type: "appScreenshots",
          attributes: {
            fileName: screenshot.fileName,
            fileSize: screenshot.fileSize,
          },
          relationships: {
            appScreenshotSet: {
              data: { type: "appScreenshotSets", id: screenshotSetId },
            },
          },
        },
      },
    })
  ).data;
}

async function commitAppScreenshot(token, screenshotResource, screenshot) {
  return (
    await ascFetch(token, `/appScreenshots/${screenshotResource.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appScreenshots",
          id: screenshotResource.id,
          attributes: {
            uploaded: true,
            sourceFileChecksum: screenshot.sourceFileChecksum,
          },
        },
      },
    })
  ).data;
}

async function waitForAppScreenshot(token, screenshotId) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const response = await ascFetch(
      token,
      `/appScreenshots/${screenshotId}?fields[appScreenshots]=fileName,fileSize,sourceFileChecksum,imageAsset,assetDeliveryState`
    );
    const state = response.data?.attributes?.assetDeliveryState?.state;
    if (state === "COMPLETE") return response.data;
    if (state === "FAILED") {
      throw new Error(
        `Screenshot ${screenshotId} failed processing: ${JSON.stringify(
          response.data?.attributes?.assetDeliveryState
        )}`
      );
    }
    await sleep(1000);
  }
  throw new Error(`Screenshot ${screenshotId} did not process within 2 minutes`);
}

async function reorderAppScreenshots(token, screenshotSetId, screenshotIds) {
  await ascFetch(
    token,
    `/appScreenshotSets/${screenshotSetId}/relationships/appScreenshots`,
    {
      method: "PATCH",
      body: {
        data: screenshotIds.map((id) => ({ type: "appScreenshots", id })),
      },
    }
  );
}

async function replaceScreenshots(
  token,
  localizationId,
  directoryPath,
  screenshotDisplayType,
  supportedSizes,
  sizeDescription
) {
  const desired = validatedScreenshotFiles(
    directoryPath,
    supportedSizes,
    sizeDescription
  );
  const sets = await readScreenshotSets(token, localizationId);
  const screenshotSet = sets.find(
    (set) => set.screenshotDisplayType === screenshotDisplayType
  );
  if (!screenshotSet) {
    throw new Error(
      `No ${screenshotDisplayType} screenshot set exists for ${LOCALE}`
    );
  }

  const available = [...screenshotSet.screenshots];
  const selected = [];
  for (const screenshot of desired) {
    const reusableIndex = available.findIndex(
      (item) =>
        item.sourceFileChecksum?.toLowerCase() ===
          screenshot.sourceFileChecksum.toLowerCase() &&
        item.assetDeliveryState?.state === "COMPLETE"
    );
    if (reusableIndex >= 0) {
      selected.push(available.splice(reusableIndex, 1)[0]);
      continue;
    }

    let resource = await createAppScreenshot(token, screenshotSet.id, screenshot);
    await uploadAsset(screenshot.filePath, resource.attributes?.uploadOperations);
    resource = await commitAppScreenshot(token, resource, screenshot);
    selected.push(await waitForAppScreenshot(token, resource.id));
  }

  for (const screenshot of available) {
    await ascFetch(token, `/appScreenshots/${screenshot.id}`, {
      method: "DELETE",
    });
  }
  await reorderAppScreenshots(
    token,
    screenshotSet.id,
    selected.map((screenshot) => screenshot.id)
  );

  return {
    screenshotSetId: screenshotSet.id,
    screenshotDisplayType: screenshotSet.screenshotDisplayType,
    screenshots: selected.map((screenshot) => ({
      id: screenshot.id,
      fileName: screenshot.attributes?.fileName ?? screenshot.fileName,
    })),
  };
}

async function replaceIphoneScreenshots(token, localizationId, directoryPath) {
  return replaceScreenshots(
    token,
    localizationId,
    directoryPath,
    IPHONE_SCREENSHOT_DISPLAY_TYPE,
    IPHONE_SCREENSHOT_SIZES,
    "a supported 6.9-inch iPhone portrait size"
  );
}

async function replaceIpadScreenshots(token, localizationId, directoryPath) {
  return replaceScreenshots(
    token,
    localizationId,
    directoryPath,
    IPAD_SCREENSHOT_DISPLAY_TYPE,
    IPAD_SCREENSHOT_SIZES,
    "a supported 13-inch iPad portrait size"
  );
}

async function findAppInfo(token, appId) {
  const appInfos = await listAll(
    token,
    `/apps/${appId}/appInfos?fields[appInfos]=appStoreState,appStoreAgeRating,primaryCategory,secondaryCategory&limit=20`
  );
  const editableStates = new Set([
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
  ]);
  const appInfo =
    appInfos.find((item) => editableStates.has(item.attributes?.appStoreState)) ??
    appInfos[0];
  if (!appInfo) throw new Error(`No app info found for ${appId}`);
  return appInfo;
}

async function applyAppInfoLocalization(token, appInfoId) {
  const localizations = await listAll(
    token,
    `/appInfos/${appInfoId}/appInfoLocalizations?fields[appInfoLocalizations]=locale,name,privacyPolicyUrl,subtitle&limit=200`
  );
  const localization = localizations.find(
    (item) => item.attributes?.locale === LOCALE
  );
  if (!localization) throw new Error(`No ${LOCALE} app info localization found`);

  return (
    await ascFetch(token, `/appInfoLocalizations/${localization.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appInfoLocalizations",
          id: localization.id,
          attributes: {
            subtitle: LISTING.subtitle,
            privacyPolicyUrl: URLS.privacy,
          },
        },
      },
    })
  ).data;
}

async function readAgeRating(token, appInfoId) {
  return optionalFetch(
    token,
    `/appInfos/${appInfoId}/ageRatingDeclaration?fields[ageRatingDeclarations]=${Object.keys(
      AGE_RATING
    ).join(",")}`
  );
}

async function applyAgeRating(token, appInfoId) {
  const current = await readAgeRating(token, appInfoId);
  if (!current?.data?.id) throw new Error("No age rating declaration found");
  return (
    await ascFetch(token, `/ageRatingDeclarations/${current.data.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "ageRatingDeclarations",
          id: current.data.id,
          attributes: AGE_RATING,
        },
      },
    })
  ).data;
}

async function readReviewDetail(token, versionId) {
  return optionalFetch(
    token,
    `/appStoreVersions/${versionId}/appStoreReviewDetail?fields[appStoreReviewDetails]=contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,demoAccountName,demoAccountPassword,notes`
  );
}

async function sourceReviewContact(token, versions, targetVersionId) {
  for (const version of versions) {
    if (version.id === targetVersionId) continue;
    const review = await readReviewDetail(token, version.id);
    const attributes = review?.data?.attributes;
    if (
      attributes?.contactFirstName &&
      attributes?.contactLastName &&
      attributes?.contactPhone &&
      attributes?.contactEmail
    ) {
      return attributes;
    }
  }
  return null;
}

function reviewContactAttributes(source) {
  const attributes = {
    contactFirstName: process.env.ASC_REVIEW_FIRST_NAME ?? source?.contactFirstName,
    contactLastName: process.env.ASC_REVIEW_LAST_NAME ?? source?.contactLastName,
    contactPhone: process.env.ASC_REVIEW_PHONE ?? source?.contactPhone,
    contactEmail: process.env.ASC_REVIEW_EMAIL ?? source?.contactEmail,
  };
  if (Object.values(attributes).some((value) => !value)) {
    throw new Error(
      "Missing App Review contact details. Set ASC_REVIEW_FIRST_NAME, ASC_REVIEW_LAST_NAME, ASC_REVIEW_PHONE, and ASC_REVIEW_EMAIL."
    );
  }
  return attributes;
}

async function applyReviewDetail(token, versionId, versions) {
  const existing = await readReviewDetail(token, versionId);
  const source = existing?.data?.attributes ??
    (await sourceReviewContact(token, versions, versionId));
  const attributes = {
    ...reviewContactAttributes(source),
    demoAccountRequired: false,
    demoAccountName: "",
    demoAccountPassword: "",
    notes: REVIEW_NOTES,
  };

  if (existing?.data?.id) {
    return (
      await ascFetch(token, `/appStoreReviewDetails/${existing.data.id}`, {
        method: "PATCH",
        body: {
          data: {
            type: "appStoreReviewDetails",
            id: existing.data.id,
            attributes,
          },
        },
      })
    ).data;
  }

  return (
    await ascFetch(token, "/appStoreReviewDetails", {
      method: "POST",
      body: {
        data: {
          type: "appStoreReviewDetails",
          attributes,
          relationships: {
            appStoreVersion: {
              data: { type: "appStoreVersions", id: versionId },
            },
          },
        },
      },
    })
  ).data;
}

async function applyServerNotifications(token, appId, url) {
  new URL(url);
  return (
    await ascFetch(token, `/apps/${appId}`, {
      method: "PATCH",
      body: {
        data: {
          type: "apps",
          id: appId,
          attributes: {
            subscriptionStatusUrl: url,
            subscriptionStatusUrlVersion: "V2",
            subscriptionStatusUrlForSandbox: url,
            subscriptionStatusUrlVersionForSandbox: "V2",
          },
        },
      },
    })
  ).data;
}

async function listBuilds(token, appId) {
  return listAll(
    token,
    `/builds?filter[app]=${appId}&filter[version]=${BUILD_NUMBER}&fields[builds]=version,uploadedDate,processingState,expired,usesNonExemptEncryption&include=preReleaseVersion&fields[preReleaseVersions]=version,platform&limit=200`
  );
}

function matchingBuild(builds, included = []) {
  const prereleaseById = new Map(included.map((item) => [item.id, item]));
  return builds.find((build) => {
    if (build.attributes?.version !== BUILD_NUMBER) return false;
    const prereleaseId = build.relationships?.preReleaseVersion?.data?.id;
    return prereleaseById.get(prereleaseId)?.attributes?.version === VERSION;
  });
}

async function findBuild(token, appId) {
  const response = await ascFetch(
    token,
    `/builds?filter[app]=${appId}&filter[version]=${BUILD_NUMBER}&fields[builds]=version,uploadedDate,processingState,expired,usesNonExemptEncryption&include=preReleaseVersion&fields[preReleaseVersions]=version,platform&limit=200`
  );
  return matchingBuild(response.data ?? [], response.included ?? []) ?? null;
}

async function listMatchingBuildUploads(token, appId) {
  const uploads = await listAll(
    token,
    `/apps/${appId}/buildUploads?fields[buildUploads]=cfBundleShortVersionString,cfBundleVersion,createdDate,state,platform,uploadedDate&limit=200`
  );
  return uploads
    .filter(
      (upload) =>
        upload.attributes?.cfBundleShortVersionString === VERSION &&
        upload.attributes?.cfBundleVersion === BUILD_NUMBER
    )
    .sort((left, right) =>
      String(right.attributes?.createdDate).localeCompare(
        String(left.attributes?.createdDate)
      )
    );
}

async function latestCompletedBuildUploadReference(token, appId) {
  const uploads = await listAll(
    token,
    `/apps/${appId}/buildUploads?filter[state]=COMPLETE&fields[buildUploads]=cfBundleShortVersionString,cfBundleVersion,createdDate,state,platform,uploadedDate&sort=-uploadedDate&limit=10`
  );
  const upload = uploads[0];
  if (!upload) return null;
  const files = await listBuildUploadFiles(token, upload.id);
  return {
    id: upload.id,
    ...upload.attributes,
    files: files.map((file) => ({
      id: file.id,
      assetType: file.attributes?.assetType,
      fileName: file.attributes?.fileName,
      fileSize: file.attributes?.fileSize,
      uti: file.attributes?.uti,
      assetDeliveryState: file.attributes?.assetDeliveryState,
      sourceFileChecksums: file.attributes?.sourceFileChecksums,
    })),
  };
}

async function createBuildUpload(token, appId) {
  return (
    await ascFetch(token, "/buildUploads", {
      method: "POST",
      body: {
        data: {
          type: "buildUploads",
          attributes: {
            cfBundleShortVersionString: VERSION,
            cfBundleVersion: BUILD_NUMBER,
            platform: "IOS",
          },
          relationships: {
            app: { data: { type: "apps", id: appId } },
          },
        },
      },
    })
  ).data;
}

async function listBuildUploadFiles(token, uploadId) {
  return listAll(
    token,
    `/buildUploads/${uploadId}/buildUploadFiles?fields[buildUploadFiles]=assetDeliveryState,assetToken,assetType,fileName,fileSize,sourceFileChecksums,uploadOperations,uti&limit=200`
  );
}

async function createBuildUploadFile(token, uploadId, ipaPath) {
  return (
    await ascFetch(token, "/buildUploadFiles", {
      method: "POST",
      body: {
        data: {
          type: "buildUploadFiles",
          attributes: {
            assetType: "ASSET",
            fileName: path.basename(ipaPath),
            fileSize: fs.statSync(ipaPath).size,
            uti: "com.apple.ipa",
          },
          relationships: {
            buildUpload: {
              data: { type: "buildUploads", id: uploadId },
            },
          },
        },
      },
    })
  ).data;
}

async function uploadAsset(filePath, operations) {
  const file = fs.readFileSync(filePath);
  for (const operation of operations ?? []) {
    const offset = Number(operation.offset ?? 0);
    const length = Number(operation.length ?? file.length);
    const headers = {};
    for (const header of operation.requestHeaders ?? []) {
      headers[header.name] = header.value;
    }
    const response = await fetch(operation.url, {
      method: operation.method ?? "PUT",
      headers,
      body: file.subarray(offset, offset + length),
    });
    if (!response.ok) {
      throw new Error(
        `Asset upload operation failed ${response.status}: ${await response.text()}`
      );
    }
  }
}

function buildUploadChecksums(filePath, operations) {
  const file = fs.readFileSync(filePath);
  const parts = [...(operations ?? [])].sort(
    (left, right) => Number(left.offset ?? 0) - Number(right.offset ?? 0)
  );
  const normalizedParts = parts.length > 0
    ? parts
    : [{ offset: 0, length: file.length }];
  const partDigests = normalizedParts.map((operation) => {
    const offset = Number(operation.offset ?? 0);
    const length = Number(operation.length ?? file.length);
    return crypto
      .createHash("md5")
      .update(file.subarray(offset, offset + length))
      .digest();
  });
  const partSize = Number(normalizedParts[0].length ?? file.length);
  const fileHash = crypto.createHash("md5").update(file).digest("hex").toUpperCase();
  const compositeHash = crypto
    .createHash("md5")
    .update(Buffer.concat(partDigests))
    .digest("hex")
    .toUpperCase();
  return {
    file: { hash: fileHash, algorithm: "MD5" },
    composite: {
      hash: `${compositeHash}-${partDigests.length}-${partSize}`,
      algorithm: "MD5",
    },
  };
}

async function commitBuildUploadFile(token, fileResource, ipaPath) {
  const sourceFileChecksums = buildUploadChecksums(
    ipaPath,
    fileResource.attributes?.uploadOperations
  );
  return (
    await ascFetch(token, `/buildUploadFiles/${fileResource.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "buildUploadFiles",
          id: fileResource.id,
          attributes: {
            uploaded: true,
            sourceFileChecksums,
          },
        },
      },
    })
  ).data;
}

async function readBuildUpload(token, uploadId) {
  return (
    await ascFetch(
      token,
      `/buildUploads/${uploadId}?fields[buildUploads]=cfBundleShortVersionString,cfBundleVersion,createdDate,state,platform,uploadedDate`
    )
  ).data;
}

async function waitForBuildUpload(token, uploadId) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const upload = await readBuildUpload(token, uploadId);
    const state = upload.attributes?.state?.state;
    if (state === "COMPLETE") return upload;
    if (state === "FAILED") {
      throw new Error(
        `Build upload failed: ${JSON.stringify(upload.attributes?.state)}`
      );
    }
    await sleep(5000);
  }
  throw new Error(`Build upload ${uploadId} did not complete within 10 minutes`);
}

async function waitForBuild(token, appId) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const build = await findBuild(token, appId);
    if (build?.attributes?.processingState === "VALID") return build;
    if (build?.attributes?.processingState === "FAILED") {
      throw new Error(`Build ${BUILD_NUMBER} failed App Store processing`);
    }
    await sleep(5000);
  }
  throw new Error(`Build ${BUILD_NUMBER} did not become valid within 10 minutes`);
}

async function uploadIpa(token, appId, ipaPath) {
  if (!fs.existsSync(ipaPath)) throw new Error(`IPA does not exist: ${ipaPath}`);
  const existingBuild = await findBuild(token, appId);
  if (existingBuild) {
    return { skipped: true, reason: "Build already exists", build: existingBuild };
  }

  const matchingUploads = await listMatchingBuildUploads(token, appId);
  let upload = matchingUploads.find(
    (item) => item.attributes?.state?.state !== "FAILED"
  );
  if (!upload) upload = await createBuildUpload(token, appId);

  if (upload.attributes?.state?.state === "AWAITING_UPLOAD") {
    const files = await listBuildUploadFiles(token, upload.id);
    let fileResource = files.find(
      (file) => file.attributes?.assetType === "ASSET"
    );
    if (!fileResource) {
      fileResource = await createBuildUploadFile(token, upload.id, ipaPath);
    }
    const assetState = fileResource.attributes?.assetDeliveryState?.state;
    if (!assetState || assetState === "AWAITING_UPLOAD") {
      await uploadAsset(ipaPath, fileResource.attributes?.uploadOperations);
      fileResource = await commitBuildUploadFile(token, fileResource, ipaPath);
    }
  }

  const completedUpload = await waitForBuildUpload(token, upload.id);
  const build = await waitForBuild(token, appId);
  return { skipped: false, upload: completedUpload, build };
}

async function attachBuild(token, versionId, buildId) {
  await ascFetch(token, `/appStoreVersions/${versionId}/relationships/build`, {
    method: "PATCH",
    body: { data: { type: "builds", id: buildId } },
  });
}

function safeReviewSummary(review) {
  const attributes = review?.data?.attributes;
  if (!attributes) return null;
  return {
    id: review.data.id,
    contactFirstName: attributes.contactFirstName,
    contactLastName: attributes.contactLastName,
    contactPhonePresent: Boolean(attributes.contactPhone),
    contactEmail: attributes.contactEmail,
    demoAccountRequired: attributes.demoAccountRequired,
    demoAccountNamePresent: Boolean(attributes.demoAccountName),
    demoAccountPasswordPresent: Boolean(attributes.demoAccountPassword),
    notesLength: attributes.notes?.length ?? 0,
  };
}

async function audit(token, app, version, appInfo) {
  const versionLocalization = version
    ? (await listAll(
        token,
        `/appStoreVersions/${version.id}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,description,keywords,marketingUrl,promotionalText,supportUrl,whatsNew&limit=200`
      )).find((item) => item.attributes?.locale === LOCALE) ?? null
    : null;
  const appInfoLocalization = (
    await listAll(
      token,
      `/appInfos/${appInfo.id}/appInfoLocalizations?fields[appInfoLocalizations]=locale,name,privacyPolicyUrl,subtitle&limit=200`
    )
  ).find((item) => item.attributes?.locale === LOCALE) ?? null;
  const ageRating = await readAgeRating(token, appInfo.id);
  const review = version ? await readReviewDetail(token, version.id) : null;
  const screenshotSets = versionLocalization
    ? await readScreenshotSets(token, versionLocalization.id)
    : [];
  const build = await findBuild(token, app.id);
  const uploads = await listMatchingBuildUploads(token, app.id);
  const completedUploadReference = await latestCompletedBuildUploadReference(
    token,
    app.id
  );
  const uploadSummaries = [];
  for (const upload of uploads) {
    const files = await listBuildUploadFiles(token, upload.id);
    uploadSummaries.push({
      id: upload.id,
      ...upload.attributes,
      files: files.map((file) => ({
        id: file.id,
        assetType: file.attributes?.assetType,
        fileName: file.attributes?.fileName,
        fileSize: file.attributes?.fileSize,
        uti: file.attributes?.uti,
        assetDeliveryState: file.attributes?.assetDeliveryState,
        sourceFileChecksums: file.attributes?.sourceFileChecksums,
      })),
    });
  }

  return {
    app: { id: app.id, ...app.attributes },
    target: { version: VERSION, build: BUILD_NUMBER },
    version: version ? { id: version.id, ...version.attributes } : null,
    versionLocalization: versionLocalization
      ? { id: versionLocalization.id, ...versionLocalization.attributes }
      : null,
    appInfo: { id: appInfo.id, ...appInfo.attributes },
    appInfoLocalization: appInfoLocalization
      ? { id: appInfoLocalization.id, ...appInfoLocalization.attributes }
      : null,
    ageRating: ageRating?.data
      ? { id: ageRating.data.id, ...ageRating.data.attributes }
      : null,
    review: safeReviewSummary(review),
    screenshotSets,
    build: build ? { id: build.id, ...build.attributes } : null,
    buildUploads: uploadSummaries,
    completedBuildUploadReference: completedUploadReference,
  };
}

loadEnv(path.join(ROOT, ".env.local"));
validateMetadata();

const applyMetadata = process.argv.includes("--apply-metadata");
const applyReview = process.argv.includes("--apply-review");
const applyAge = process.argv.includes("--apply-age-rating");
const attachBuildWhenReady = process.argv.includes("--attach-build");
const serverUrl = argumentValue("--apply-server-url");
const ipaPath = argumentValue("--upload-ipa");
const iphoneScreenshotsDirectory = argumentValue(
  "--replace-iphone-screenshots-dir"
);
const ipadScreenshotsDirectory = argumentValue(
  "--replace-ipad-screenshots-dir"
);

const token = await getToken();
let app = await findApp(token);
let versions = await listVersions(token, app.id);
let version = versions.find(
  (item) => item.attributes?.versionString === VERSION
) ?? null;
const appInfo = await findAppInfo(token, app.id);

if (
  applyMetadata ||
  applyReview ||
  applyAge ||
  attachBuildWhenReady ||
  iphoneScreenshotsDirectory ||
  ipadScreenshotsDirectory
) {
  version = version ?? (await ensureVersion(token, app.id));
  versions = await listVersions(token, app.id);
}

if (applyMetadata) {
  version = await patchVersion(token, version.id);
  await applyVersionLocalization(token, version.id);
  await applyAppInfoLocalization(token, appInfo.id);
}

if (applyReview) {
  await applyReviewDetail(token, version.id, versions);
}

if (applyAge) {
  await applyAgeRating(token, appInfo.id);
}

if (serverUrl) {
  app = await applyServerNotifications(token, app.id, serverUrl);
}

let replacedIphoneScreenshots = null;
if (iphoneScreenshotsDirectory) {
  const localization = await ensureVersionLocalization(token, version.id);
  replacedIphoneScreenshots = await replaceIphoneScreenshots(
    token,
    localization.id,
    iphoneScreenshotsDirectory
  );
}

let replacedIpadScreenshots = null;
if (ipadScreenshotsDirectory) {
  const localization = await ensureVersionLocalization(token, version.id);
  replacedIpadScreenshots = await replaceIpadScreenshots(
    token,
    localization.id,
    ipadScreenshotsDirectory
  );
}

let uploadedBuild = null;
if (ipaPath) {
  uploadedBuild = await uploadIpa(token, app.id, ipaPath);
}

if (attachBuildWhenReady) {
  const build = uploadedBuild?.build ?? (await waitForBuild(token, app.id));
  await attachBuild(token, version.id, build.id);
}

versions = await listVersions(token, app.id);
version = versions.find((item) => item.attributes?.versionString === VERSION) ?? null;
const result = await audit(token, await findApp(token), version, appInfo);
result.actions = {
  applyMetadata,
  applyReview,
  applyAge,
  serverUrlApplied: Boolean(serverUrl),
  replacedIphoneScreenshots,
  replacedIpadScreenshots,
  ipaUpload: uploadedBuild
    ? {
        skipped: uploadedBuild.skipped,
        reason: uploadedBuild.reason ?? null,
        buildId: uploadedBuild.build?.id ?? null,
        processingState: uploadedBuild.build?.attributes?.processingState ?? null,
        uploadId: uploadedBuild.upload?.id ?? null,
      }
    : null,
  attachBuildWhenReady,
};

console.log(JSON.stringify(result, null, 2));
