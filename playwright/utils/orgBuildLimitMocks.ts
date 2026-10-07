/*
 * SPDX-License-Identifier: Apache-2.0
 */

import { Page } from '@playwright/test';
import {
  jsonResponse,
  resolvePayload,
  textResponse,
  withGet,
  withMethod,
} from './http';
import { orgBuildLimitPattern } from './routes';

export async function mockOrgBuildLimit(
  page: Page,
  payloadOrFixture: string | unknown,
): Promise<void> {
  await page.route(orgBuildLimitPattern, route =>
    withGet(route, () =>
      jsonResponse(route, { body: resolvePayload(payloadOrFixture) }),
    ),
  );
}

export async function mockOrgBuildLimitError(
  page: Page,
  status = 500,
  body = 'server error',
): Promise<void> {
  await page.route(orgBuildLimitPattern, route =>
    withGet(route, () => textResponse(route, { status, body })),
  );
}

export async function mockOrgBuildLimitUpdate(
  page: Page,
  payloadOrFixture: string | unknown,
  status = 200,
): Promise<void> {
  await page.route(orgBuildLimitPattern, route =>
    withMethod(route, 'PUT', () =>
      jsonResponse(route, {
        status,
        body: resolvePayload(payloadOrFixture),
      }),
    ),
  );
}

export async function mockOrgBuildLimitUpdateError(
  page: Page,
  status = 403,
  error = 'organization build limits have been disabled by Vela admins',
): Promise<void> {
  await page.route(orgBuildLimitPattern, route =>
    withMethod(route, 'PUT', () =>
      jsonResponse(route, { status, body: { error } }),
    ),
  );
}

export async function mockOrgBuildLimitDelete(
  page: Page,
  message = 'build limit override for organization github deleted',
): Promise<void> {
  await page.route(orgBuildLimitPattern, route =>
    withMethod(route, 'DELETE', () => jsonResponse(route, { body: message })),
  );
}
