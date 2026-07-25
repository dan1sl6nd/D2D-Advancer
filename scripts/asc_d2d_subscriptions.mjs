import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { SignJWT, importPKCS8 } from "jose";

const ROOT = process.cwd();
const BUNDLE_ID = "dan1sland.D2D-Advancer";
const GROUP_REFERENCE_NAME = "Premium Access";
const GROUP_DISPLAY_NAME = "D2D Advancer Premium";
const LOCALE = "en-US";
const LEGACY_SOLO_PRODUCT_IDS = new Set([
  "com.d2dadvancer.weekly",
  "com.d2dadvancer.yearly",
]);

const plans = [
  {
    key: "soloYearly",
    productId: "com.d2dadvancer.solo.yearly",
    referenceName: "D2D Advancer Solo Yearly",
    displayName: "Solo Yearly",
    description: "Private field sales CRM for one person.",
    period: "ONE_YEAR",
    planType: "UPFRONT",
    usaPrice: "119.99",
    groupLevel: 2,
    introductoryTrial: "TWO_WEEKS",
  },
  {
    key: "soloMonthly",
    productId: "com.d2dadvancer.solo.monthly",
    referenceName: "D2D Advancer Solo Monthly",
    displayName: "Solo Monthly",
    description: "Private field sales CRM for one person.",
    period: "ONE_MONTH",
    planType: "UPFRONT",
    usaPrice: "14.99",
    groupLevel: 2,
  },
  {
    key: "teamYearly",
    productId: "com.d2dadvancer.team3.yearly",
    referenceName: "D2D Advancer Team Yearly",
    displayName: "Team Yearly",
    description: "Shared work for one owner and two workers.",
    period: "ONE_YEAR",
    planType: "UPFRONT",
    usaPrice: "319.99",
    groupLevel: 1,
    introductoryTrial: "TWO_WEEKS",
  },
  {
    key: "teamMonthly",
    productId: "com.d2dadvancer.team3.monthly",
    referenceName: "D2D Advancer Team Monthly",
    displayName: "Team Monthly",
    description: "Shared work for one owner and two workers.",
    period: "ONE_MONTH",
    planType: "UPFRONT",
    usaPrice: "39.99",
    groupLevel: 1,
  },
];

const reviewNote =
  "Open the subscription screen from onboarding or More. Solo unlocks the private field-sales workspace. Team includes Solo plus one owner and two worker seats for assigned leads, service jobs, alerts, and manual on-duty location sharing.";

function loadEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const match = line.trim().match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match || process.env[match[1]]) continue;
    process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, "");
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

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
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
  const text = await response.text();
  if (!response.ok) {
    const retryableRead =
      method === "GET" &&
      (response.status === 429 || response.status >= 500) &&
      attempt < 4;
    if (retryableRead) {
      await sleep(500 * 2 ** attempt);
      return ascFetch(token, route, options, attempt + 1);
    }
    throw new Error(`ASC API ${response.status} for ${route}: ${text}`);
  }
  return text ? JSON.parse(text) : {};
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
    `/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name,bundleId,sku,primaryLocale`
  );
  const app = response.data?.[0];
  if (!app) throw new Error(`No App Store Connect app found for ${BUNDLE_ID}`);
  return app;
}

async function ensureGroup(token, appId) {
  const groups = await listAll(
    token,
    `/apps/${appId}/subscriptionGroups?fields[subscriptionGroups]=referenceName`
  );
  const existing = groups.find(
    (group) => group.attributes?.referenceName === GROUP_REFERENCE_NAME
  );
  if (existing) return existing;

  return (
    await ascFetch(token, "/subscriptionGroups", {
      method: "POST",
      body: {
        data: {
          type: "subscriptionGroups",
          attributes: { referenceName: GROUP_REFERENCE_NAME },
          relationships: {
            app: { data: { type: "apps", id: appId } },
          },
        },
      },
    })
  ).data;
}

async function ensureGroupLocalization(token, groupId) {
  const localizations = await listAll(
    token,
    `/subscriptionGroups/${groupId}/subscriptionGroupLocalizations?fields[subscriptionGroupLocalizations]=name,customAppName,locale,state`
  );
  const existing = localizations.find((item) => item.attributes?.locale === LOCALE);
  const attributes = { locale: LOCALE, name: GROUP_DISPLAY_NAME };

  if (!existing) {
    return (
      await ascFetch(token, "/subscriptionGroupLocalizations", {
        method: "POST",
        body: {
          data: {
            type: "subscriptionGroupLocalizations",
            attributes,
            relationships: {
              subscriptionGroup: {
                data: { type: "subscriptionGroups", id: groupId },
              },
            },
          },
        },
      })
    ).data;
  }

  if (existing.attributes?.name !== GROUP_DISPLAY_NAME) {
    return (
      await ascFetch(token, `/subscriptionGroupLocalizations/${existing.id}`, {
        method: "PATCH",
        body: {
          data: {
            type: "subscriptionGroupLocalizations",
            id: existing.id,
            attributes: { name: GROUP_DISPLAY_NAME },
          },
        },
      })
    ).data;
  }
  return existing;
}

async function ensureSubscription(token, groupId, plan) {
  const subscriptions = await listAll(
    token,
    `/subscriptionGroups/${groupId}/subscriptions?fields[subscriptions]=name,productId,state,subscriptionPeriod,groupLevel,familySharable,reviewNote`
  );
  const existing = subscriptions.find(
    (subscription) => subscription.attributes?.productId === plan.productId
  );
  if (existing) {
    const desired = {
      name: plan.referenceName,
      subscriptionPeriod: plan.period,
      familySharable: false,
      reviewNote,
      groupLevel: plan.groupLevel,
    };
    const needsUpdate = Object.entries(desired).some(
      ([key, value]) => existing.attributes?.[key] !== value
    );
    if (!needsUpdate) return existing;

    return (
      await ascFetch(token, `/subscriptions/${existing.id}`, {
        method: "PATCH",
        body: {
          data: {
            type: "subscriptions",
            id: existing.id,
            attributes: desired,
          },
        },
      })
    ).data;
  }

  return (
    await ascFetch(token, "/subscriptions", {
      method: "POST",
      body: {
        data: {
          type: "subscriptions",
          attributes: {
            name: plan.referenceName,
            productId: plan.productId,
            subscriptionPeriod: plan.period,
            familySharable: false,
            reviewNote,
            groupLevel: plan.groupLevel,
          },
          relationships: {
            group: {
              data: { type: "subscriptionGroups", id: groupId },
            },
          },
        },
      },
    })
  ).data;
}

async function adoptLegacySubscriptionLevels(token, groupId) {
  const subscriptions = await listAll(
    token,
    `/subscriptionGroups/${groupId}/subscriptions?fields[subscriptions]=name,productId,state,subscriptionPeriod,groupLevel,familySharable,reviewNote`
  );
  for (const subscription of subscriptions) {
    if (
      LEGACY_SOLO_PRODUCT_IDS.has(subscription.attributes?.productId) &&
      subscription.attributes?.groupLevel !== 2
    ) {
      await ascFetch(token, `/subscriptions/${subscription.id}`, {
        method: "PATCH",
        body: {
          data: {
            type: "subscriptions",
            id: subscription.id,
            attributes: { groupLevel: 2 },
          },
        },
      });
    }
  }
}

async function ensureSubscriptionLocalization(token, subscriptionId, plan) {
  const localizations = await listAll(
    token,
    `/subscriptions/${subscriptionId}/subscriptionLocalizations?fields[subscriptionLocalizations]=name,description,locale,state`
  );
  const existing = localizations.find((item) => item.attributes?.locale === LOCALE);
  const attributes = {
    locale: LOCALE,
    name: plan.displayName,
    description: plan.description,
  };

  if (!existing) {
    return (
      await ascFetch(token, "/subscriptionLocalizations", {
        method: "POST",
        body: {
          data: {
            type: "subscriptionLocalizations",
            attributes,
            relationships: {
              subscription: {
                data: { type: "subscriptions", id: subscriptionId },
              },
            },
          },
        },
      })
    ).data;
  }

  if (
    existing.attributes?.name !== plan.displayName ||
    existing.attributes?.description !== plan.description
  ) {
    return (
      await ascFetch(token, `/subscriptionLocalizations/${existing.id}`, {
        method: "PATCH",
        body: {
          data: {
            type: "subscriptionLocalizations",
            id: existing.id,
            attributes: {
              name: plan.displayName,
              description: plan.description,
            },
          },
        },
      })
    ).data;
  }
  return existing;
}

function priceMatches(actual, expected) {
  return Number(actual).toFixed(2) === Number(expected).toFixed(2);
}

function territoryId(resource) {
  return resource.relationships?.territory?.data?.id ?? null;
}

function subscriptionPricePointId(resource) {
  return resource.relationships?.subscriptionPricePoint?.data?.id ?? null;
}

async function activeUsaCustomerPrice(token, prices) {
  const today = isoDate();
  const currentPrices = prices
    .filter(
      (price) =>
        territoryId(price) === "USA" &&
        price.attributes?.planType === "UPFRONT" &&
        (!price.attributes?.startDate || price.attributes.startDate <= today)
    )
    .sort((left, right) =>
      String(right.attributes?.startDate ?? "").localeCompare(
        String(left.attributes?.startDate ?? "")
      )
    );
  const pricePointId = subscriptionPricePointId(currentPrices[0]);
  if (!pricePointId) return null;

  const response = await ascFetch(
    token,
    `/subscriptionPricePoints/${encodeURIComponent(pricePointId)}?fields[subscriptionPricePoints]=customerPrice,territory&include=territory`
  );
  return response.data?.attributes?.customerPrice ?? null;
}

async function allTerritories(token) {
  return listAll(token, "/territories?fields[territories]=currency&limit=200");
}

async function ensurePlanAvailability(token, subscriptionId, plan, territories) {
  const availabilities = await listAll(
    token,
    `/subscriptions/${subscriptionId}/planAvailabilities?fields[subscriptionPlanAvailabilities]=availableInNewTerritories,planType`
  );
  let availability = availabilities.find(
    (item) => item.attributes?.planType === plan.planType
  );
  const availableTerritories = {
    data: territories.map((territory) => ({ type: "territories", id: territory.id })),
  };

  if (!availability) {
    availability = (
      await ascFetch(token, "/subscriptionPlanAvailabilities", {
        method: "POST",
        body: {
          data: {
            type: "subscriptionPlanAvailabilities",
            attributes: {
              planType: plan.planType,
              availableInNewTerritories: true,
            },
            relationships: {
              subscription: {
                data: { type: "subscriptions", id: subscriptionId },
              },
              availableTerritories,
            },
          },
        },
      })
    ).data;
  } else {
    await ascFetch(
      token,
      `/subscriptionPlanAvailabilities/${availability.id}/relationships/availableTerritories`,
      {
        method: "PATCH",
        body: availableTerritories,
      }
    );
    if (!availability.attributes?.availableInNewTerritories) {
      availability = (
        await ascFetch(token, `/subscriptionPlanAvailabilities/${availability.id}`, {
          method: "PATCH",
          body: {
            data: {
              type: "subscriptionPlanAvailabilities",
              id: availability.id,
              attributes: { availableInNewTerritories: true },
            },
          },
        })
      ).data;
    }
  }
  return availability;
}

function isoDate(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function isCurrentOrFutureOffer(offer, today) {
  const endDate = offer.attributes?.endDate;
  return !endDate || endDate >= today;
}

function isExpectedTrial(offer, plan) {
  const attributes = offer.attributes ?? {};
  return (
    attributes.offerMode === "FREE_TRIAL" &&
    attributes.duration === plan.introductoryTrial &&
    attributes.numberOfPeriods === 1 &&
    (attributes.targetSubscriptionPlanType ?? plan.planType) === plan.planType
  );
}

async function ensureIntroductoryTrial(token, subscription, plan, territories) {
  if (!plan.introductoryTrial) return { skipped: true };

  const today = isoDate();
  const offers = await listAll(
    token,
    `/subscriptions/${subscription.id}/introductoryOffers?fields[subscriptionIntroductoryOffers]=startDate,endDate,duration,offerMode,numberOfPeriods,targetSubscriptionPlanType,territory&include=territory&limit=200`
  );
  const currentOffers = offers.filter((offer) => isCurrentOrFutureOffer(offer, today));
  const conflicts = currentOffers.filter((offer) => !isExpectedTrial(offer, plan));
  if (conflicts.length > 0) {
    const conflictTerritories = conflicts.map(territoryId).filter(Boolean);
    throw new Error(
      `${plan.productId} has ${conflicts.length} current or future introductory offer(s) that do not match a ${plan.introductoryTrial} free trial. Refusing to overwrite storefronts: ${conflictTerritories.join(", ")}`
    );
  }

  const configuredTerritories = new Set(
    currentOffers.filter((offer) => isExpectedTrial(offer, plan)).map(territoryId).filter(Boolean)
  );
  const missingTerritories = territories.filter(
    (territory) => !configuredTerritories.has(territory.id)
  );

  let created = 0;
  for (const territory of missingTerritories) {
    await ascFetch(token, "/subscriptionIntroductoryOffers", {
      method: "POST",
      body: {
        data: {
          type: "subscriptionIntroductoryOffers",
          attributes: {
            startDate: today,
            duration: plan.introductoryTrial,
            offerMode: "FREE_TRIAL",
            numberOfPeriods: 1,
            targetSubscriptionPlanType: plan.planType,
          },
          relationships: {
            subscription: {
              data: { type: "subscriptions", id: subscription.id },
            },
            territory: {
              data: { type: "territories", id: territory.id },
            },
          },
        },
      },
    });
    created += 1;
    if (created % 25 === 0) {
      console.error(`${plan.productId}: created ${created}/${missingTerritories.length} trial storefronts`);
    }
  }

  return {
    created,
    alreadyConfigured: configuredTerritories.size,
    territoryCount: territories.length,
  };
}

async function pricePointsFor(token, subscriptionId, plan) {
  return listAll(
    token,
    `/subscriptions/${subscriptionId}/pricePoints?filter[territory]=USA&fields[subscriptionPricePoints]=customerPrice,proceeds,proceedsYear2,territory,equalizations&include=territory&limit=200`
  );
}

async function equalizedPricePoints(token, basePricePointId) {
  return listAll(
    token,
    `/subscriptionPricePoints/${encodeURIComponent(basePricePointId)}/equalizations?fields[subscriptionPricePoints]=customerPrice,proceeds,proceedsYear2,territory&include=territory&limit=200`
  );
}

async function ensurePrices(token, subscriptionId, plan) {
  const pricePoints = await pricePointsFor(token, subscriptionId, plan);
  const basePricePoint = pricePoints.find((item) =>
    priceMatches(item.attributes?.customerPrice, plan.usaPrice)
  );
  if (!basePricePoint) {
    throw new Error(`No USA ${plan.usaPrice} price point found for ${plan.productId}`);
  }

  const equalizations = await equalizedPricePoints(token, basePricePoint.id);
  const pointsByTerritory = new Map();
  for (const point of [basePricePoint, ...equalizations]) {
    const id = territoryId(point);
    if (id) pointsByTerritory.set(id, point);
  }

  const currentPrices = await listAll(
    token,
    `/subscriptions/${subscriptionId}/prices?fields[subscriptionPrices]=startDate,preserved,planType,territory,subscriptionPricePoint&include=territory,subscriptionPricePoint&limit=200`
  );
  const existingPointIds = new Set(
    currentPrices
      .map((price) => price.relationships?.subscriptionPricePoint?.data?.id)
      .filter(Boolean)
  );

  let created = 0;
  for (const point of pointsByTerritory.values()) {
    if (existingPointIds.has(point.id)) continue;
    let completed = false;
    for (let attempt = 0; attempt < 3 && !completed; attempt += 1) {
      try {
        await ascFetch(token, "/subscriptionPrices", {
          method: "POST",
          body: {
            data: {
              type: "subscriptionPrices",
              attributes: {
                planType: plan.planType,
                preserveCurrentPrice: false,
              },
              relationships: {
                subscription: {
                  data: { type: "subscriptions", id: subscriptionId },
                },
                subscriptionPricePoint: {
                  data: { type: "subscriptionPricePoints", id: point.id },
                },
              },
            },
          },
        });
        created += 1;
        completed = true;
      } catch (error) {
        const retryable = /ASC API (429|5\d\d)/.test(error.message);
        if (!retryable || attempt === 2) throw error;
        await sleep(750 * 2 ** attempt);
        const refreshedPrices = await listAll(
          token,
          `/subscriptions/${subscriptionId}/prices?fields[subscriptionPrices]=subscriptionPricePoint&include=subscriptionPricePoint&limit=200`
        );
        completed = refreshedPrices.some(
          (price) => price.relationships?.subscriptionPricePoint?.data?.id === point.id
        );
      }
    }
  }

  return {
    basePricePointId: basePricePoint.id,
    usaPrice: basePricePoint.attributes?.customerPrice,
    territoryCount: pointsByTerritory.size,
    created,
  };
}

async function readReviewScreenshot(token, subscriptionId) {
  try {
    return (
      await ascFetch(
        token,
        `/subscriptions/${subscriptionId}/appStoreReviewScreenshot?fields[subscriptionAppStoreReviewScreenshots]=fileSize,fileName,sourceFileChecksum,imageAsset,assetToken,assetType,uploadOperations,assetDeliveryState`
      )
    ).data;
  } catch (error) {
    if (/ASC API 404/.test(error.message)) return null;
    throw error;
  }
}

async function uploadAsset(filePath, uploadOperations) {
  const file = fs.readFileSync(filePath);
  for (const operation of uploadOperations ?? []) {
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
      throw new Error(`Screenshot upload failed ${response.status}: ${await response.text()}`);
    }
  }
}

async function ensureReviewScreenshot(token, subscriptionId, filePath) {
  const existing = await readReviewScreenshot(token, subscriptionId);
  if (existing) return existing;

  const created = await ascFetch(token, "/subscriptionAppStoreReviewScreenshots", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionAppStoreReviewScreenshots",
        attributes: {
          fileName: path.basename(filePath),
          fileSize: fs.statSync(filePath).size,
        },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
        },
      },
    },
  });
  const screenshot = created.data;
  await uploadAsset(filePath, screenshot.attributes?.uploadOperations);
  const checksum = crypto.createHash("md5").update(fs.readFileSync(filePath)).digest("hex");
  await ascFetch(token, `/subscriptionAppStoreReviewScreenshots/${screenshot.id}`, {
    method: "PATCH",
    body: {
      data: {
        type: "subscriptionAppStoreReviewScreenshots",
        id: screenshot.id,
        attributes: {
          uploaded: true,
          sourceFileChecksum: checksum,
        },
      },
    },
  });

  for (let attempt = 0; attempt < 10; attempt += 1) {
    const current = await readReviewScreenshot(token, subscriptionId);
    const state = current?.attributes?.assetDeliveryState?.state;
    if (state === "COMPLETE") return current;
    if (state === "FAILED") {
      throw new Error(`App Store Connect rejected review screenshot ${current.id}`);
    }
    await sleep(750);
  }
  return readReviewScreenshot(token, subscriptionId);
}

async function audit(token, app, group) {
  if (!group) return { app, group: null, subscriptions: [] };
  const subscriptions = await listAll(
    token,
    `/subscriptionGroups/${group.id}/subscriptions?fields[subscriptions]=name,productId,state,subscriptionPeriod,groupLevel,familySharable,reviewNote`
  );
  const details = [];
  for (const subscription of subscriptions) {
    const localizations = await listAll(
      token,
      `/subscriptions/${subscription.id}/subscriptionLocalizations?fields[subscriptionLocalizations]=name,description,locale,state`
    );
    const prices = await listAll(
      token,
      `/subscriptions/${subscription.id}/prices?fields[subscriptionPrices]=startDate,preserved,planType,territory,subscriptionPricePoint&include=territory,subscriptionPricePoint&limit=200`
    );
    const usaCustomerPrice = await activeUsaCustomerPrice(token, prices);
    const planAvailabilities = await listAll(
      token,
      `/subscriptions/${subscription.id}/planAvailabilities?fields[subscriptionPlanAvailabilities]=availableInNewTerritories,planType`
    );
    const availability = [];
    for (const item of planAvailabilities) {
      const availableTerritories = await listAll(
        token,
        `/subscriptionPlanAvailabilities/${item.id}/availableTerritories?limit=200`
      );
      availability.push({
        id: item.id,
        ...item.attributes,
        territoryCount: availableTerritories.length,
      });
    }
    const introductoryOffers = await listAll(
      token,
      `/subscriptions/${subscription.id}/introductoryOffers?fields[subscriptionIntroductoryOffers]=startDate,endDate,duration,offerMode,numberOfPeriods,targetSubscriptionPlanType,territory&include=territory&limit=200`
    );
    const reviewScreenshot = await readReviewScreenshot(token, subscription.id);
    const trialConfigurations = new Set(
      introductoryOffers.map(
        (item) =>
          `${item.attributes?.offerMode}:${item.attributes?.duration}:${item.attributes?.numberOfPeriods}:${item.attributes?.targetSubscriptionPlanType}`
      )
    );
    details.push({
      id: subscription.id,
      ...subscription.attributes,
      localizations: localizations.map((item) => ({ id: item.id, ...item.attributes })),
      priceCount: prices.length,
      usaCustomerPrice,
      availability,
      introductoryOffers: {
        count: introductoryOffers.length,
        territoryCount: new Set(introductoryOffers.map(territoryId).filter(Boolean)).size,
        configurations: [...trialConfigurations],
      },
      reviewScreenshot: reviewScreenshot
        ? {
            id: reviewScreenshot.id,
            fileName: reviewScreenshot.attributes?.fileName,
            fileSize: reviewScreenshot.attributes?.fileSize,
            assetDeliveryState: reviewScreenshot.attributes?.assetDeliveryState,
          }
        : null,
    });
  }
  return {
    app: { id: app.id, ...app.attributes },
    group: { id: group.id, ...group.attributes },
    subscriptions: details,
  };
}

loadEnv(path.join(ROOT, ".env.local"));
const applyCore = process.argv.includes("--apply-core");
const applyAvailability = process.argv.includes("--apply-availability");
const applyPricing = process.argv.includes("--apply-pricing");
const applyTrials = process.argv.includes("--apply-trials");
const uploadReviewScreenshots = process.argv.includes("--upload-review-screenshots");

function argumentValue(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : null;
}

const defaultScreenshotPath = argumentValue("--screenshot-path");
const soloScreenshotPath =
  argumentValue("--solo-screenshot-path") ?? defaultScreenshotPath;
const teamScreenshotPath =
  argumentValue("--team-screenshot-path") ?? defaultScreenshotPath;

function reviewScreenshotPath(forPlan) {
  return forPlan.key.startsWith("team") ? teamScreenshotPath : soloScreenshotPath;
}
const token = await getToken();
const app = await findApp(token);
let groups = await listAll(
  token,
  `/apps/${app.id}/subscriptionGroups?fields[subscriptionGroups]=referenceName`
);
let group = groups.find((item) => item.attributes?.referenceName === GROUP_REFERENCE_NAME);

if (applyCore) {
  group = await ensureGroup(token, app.id);
  await ensureGroupLocalization(token, group.id);
  for (const plan of plans) {
    const subscription = await ensureSubscription(token, group.id, plan);
    await ensureSubscriptionLocalization(token, subscription.id, plan);
  }
  await adoptLegacySubscriptionLevels(token, group.id);
}

if (applyAvailability || applyPricing || applyTrials || uploadReviewScreenshots) {
  if (!group) throw new Error("Create the subscription group before configuring commerce");
  const subscriptions = await listAll(
    token,
    `/subscriptionGroups/${group.id}/subscriptions?fields[subscriptions]=name,productId,state,subscriptionPeriod,groupLevel,familySharable,reviewNote`
  );
  const subscriptionsByProductId = new Map(
    subscriptions.map((subscription) => [subscription.attributes?.productId, subscription])
  );
  const territories = applyAvailability || applyTrials ? await allTerritories(token) : [];
  if (uploadReviewScreenshots) {
    const missingPaths = [
      ["Solo", soloScreenshotPath],
      ["Team", teamScreenshotPath],
    ].filter(([, filePath]) => !filePath || !fs.existsSync(filePath));
    if (missingPaths.length > 0) {
      throw new Error(
        `--upload-review-screenshots requires valid Solo and Team screenshots. Missing: ${missingPaths
          .map(([label]) => label)
          .join(", ")}. Use --solo-screenshot-path and --team-screenshot-path, or one --screenshot-path for both.`
      );
    }
  }

  for (const plan of plans) {
    const subscription = subscriptionsByProductId.get(plan.productId);
    if (!subscription) throw new Error(`Missing subscription ${plan.productId}`);
    if (applyAvailability) {
      await ensurePlanAvailability(token, subscription.id, plan, territories);
    }
    if (applyPricing) {
      console.error(JSON.stringify({ plan: plan.key, pricing: await ensurePrices(token, subscription.id, plan) }));
    }
    if (applyTrials && plan.introductoryTrial) {
      console.error(
        JSON.stringify({
          plan: plan.key,
          introductoryTrial: await ensureIntroductoryTrial(
            token,
            subscription,
            plan,
            territories
          ),
        })
      );
    }
    if (uploadReviewScreenshots) {
      const screenshot = await ensureReviewScreenshot(
        token,
        subscription.id,
        reviewScreenshotPath(plan)
      );
      console.error(
        JSON.stringify({
          plan: plan.key,
          reviewScreenshot: {
            id: screenshot.id,
            fileName: screenshot.attributes?.fileName,
            assetDeliveryState: screenshot.attributes?.assetDeliveryState,
          },
        })
      );
    }
  }
}

console.log(JSON.stringify(await audit(token, app, group), null, 2));
