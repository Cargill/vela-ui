/*
 * SPDX-License-Identifier: Apache-2.0
 */

import { Page } from '@playwright/test';
import { test, expect } from './fixtures';
import {
  mockOrgBuildLimit,
  mockOrgBuildLimitDelete,
  mockOrgBuildLimitError,
  mockOrgBuildLimitUpdate,
  mockOrgBuildLimitUpdateError,
} from './utils/orgBuildLimitMocks';
import { mockRepoDetail, mockRepoUpdate } from './utils/repoMocks';
import { orgBuildLimitPattern } from './utils/routes';
import { mockAdminSettings } from './utils/adminSettingsMocks';
import { readTestData } from './utils/testData';

async function loadOrg(page: Page, org = 'github'): Promise<void> {
  await page.getByTestId('input-org-limit-org').fill(org);
  await Promise.all([
    page.waitForResponse(
      response =>
        orgBuildLimitPattern.test(response.url()) &&
        response.request().method() === 'GET',
    ),
    page.getByTestId('button-org-limit-load').click(),
  ]);
}

test.describe('Admin Build Limits', () => {
  test.describe('as a non-admin user', () => {
    test('should redirect away from the page', async ({ page, app }) => {
      await app.login('/admin/build-limits');
      await expect(page).not.toHaveURL(/\/admin\/build-limits/);
    });
  });

  test.describe('as an admin user', () => {
    test.beforeEach(async ({ page, app }) => {
      const settings = readTestData<Record<string, unknown>>('settings.json');
      await mockAdminSettings(page, {
        ...settings,
        enable_org_build_limit: true,
      });

      await mockRepoDetail(page, 'repository.json');
      await mockRepoUpdate(page, 'repository_updated.json');

      await mockOrgBuildLimit(page, 'org_limit_default.json');
      await mockOrgBuildLimitUpdate(page, 'org_limit_updated.json', 201);
      await mockOrgBuildLimitDelete(page);
      await app.loginAdmin('/admin/build-limits');
    });

    test('should show the build limits tab', async ({ page }) => {
      await expect(page).toHaveURL(/\/admin\/build-limits/);
      await expect(page.getByTestId('org-limit')).toBeVisible();
      await expect(page.getByTestId('repo-limit')).toBeVisible();
    });

    test('org limit should not show details until loaded', async ({ page }) => {
      await expect(page.getByTestId('org-limit-details')).toHaveCount(0);
      await expect(page.getByTestId('button-org-limit-load')).toBeDisabled();
    });

    test.describe('organization limit', () => {
      test('loading an org without an override should show the server default', async ({
        page,
      }) => {
        await loadOrg(page);

        await expect(page.getByTestId('org-limit-status')).toContainText(
          'server default',
        );
        await expect(page.getByTestId('input-org-limit-value')).toHaveValue(
          '30',
        );
        await expect(page.getByTestId('button-org-limit-reset')).toHaveCount(0);
        await expect(page.getByTestId('org-limit-updated')).toHaveCount(0);
      });

      test('saving on the server default should create an override', async ({
        page,
      }) => {
        await loadOrg(page);

        // saving the default value is allowed when no override exists
        await expect(page.getByTestId('button-org-limit-save')).toBeEnabled();

        await page.getByTestId('input-org-limit-value').fill('75');
        await Promise.all([
          page.waitForResponse(
            response =>
              orgBuildLimitPattern.test(response.url()) &&
              response.request().method() === 'PUT',
          ),
          page.getByTestId('button-org-limit-save').click(),
        ]);

        await expect(page.getByTestId('alert')).toContainText(
          "Build limit for org 'github' set to '75'",
        );
        await expect(page.getByTestId('input-org-limit-value')).toHaveValue(
          '75',
        );
        await expect(page.getByTestId('org-limit-status')).toContainText(
          'custom override',
        );
      });

      test('input should not allow letter/character input', async ({
        page,
      }) => {
        await loadOrg(page);

        const input = page.getByTestId('input-org-limit-value');
        await input.fill('');
        await input.type('12cat34');
        await expect(input).toHaveValue('1234');
      });

      test('save should be disabled for a value below 1', async ({ page }) => {
        await loadOrg(page);

        await page.getByTestId('input-org-limit-value').fill('0');
        await expect(page.getByTestId('button-org-limit-save')).toBeDisabled();
      });

      test.describe('with an existing override', () => {
        test.beforeEach(async ({ page }) => {
          await mockOrgBuildLimit(page, 'org_limit.json');
          await loadOrg(page);
        });

        test('should show the override and who updated it', async ({
          page,
        }) => {
          await expect(page.getByTestId('org-limit-status')).toContainText(
            'custom override',
          );
          await expect(page.getByTestId('org-limit-updated')).toContainText(
            'octocat',
          );
          await expect(page.getByTestId('input-org-limit-value')).toHaveValue(
            '50',
          );
        });

        test('save should be disabled until the value changes', async ({
          page,
        }) => {
          await expect(
            page.getByTestId('button-org-limit-save'),
          ).toBeDisabled();

          await page.getByTestId('input-org-limit-value').fill('60');
          await expect(page.getByTestId('button-org-limit-save')).toBeEnabled();
        });

        test('reset should ask for confirmation and can be canceled', async ({
          page,
        }) => {
          await page.getByTestId('button-org-limit-reset').click();

          await expect(
            page.getByTestId('button-org-limit-reset-confirm'),
          ).toBeVisible();

          await page.getByTestId('button-org-limit-reset-cancel').click();

          await expect(
            page.getByTestId('button-org-limit-reset-confirm'),
          ).toHaveCount(0);
          await expect(
            page.getByTestId('button-org-limit-reset'),
          ).toBeVisible();
        });

        test('confirming reset should remove the override', async ({
          page,
        }) => {
          // after deleting, the page reloads the limit which is back to default
          await mockOrgBuildLimit(page, 'org_limit_default.json');

          await page.getByTestId('button-org-limit-reset').click();
          await Promise.all([
            page.waitForResponse(
              response =>
                orgBuildLimitPattern.test(response.url()) &&
                response.request().method() === 'DELETE',
            ),
            page.getByTestId('button-org-limit-reset-confirm').click(),
          ]);

          await expect(page.getByTestId('alert')).toContainText(
            "Build limit override for org 'github' removed",
          );
          await expect(page.getByTestId('org-limit-status')).toContainText(
            'server default',
          );
          await expect(page.getByTestId('button-org-limit-reset')).toHaveCount(
            0,
          );
        });
      });

      test('a 403 on save should show the disabled notice', async ({
        page,
      }) => {
        await mockOrgBuildLimitUpdateError(page, 403);
        await loadOrg(page);

        await expect(page.getByTestId('org-limit-disabled')).toHaveCount(0);

        await page.getByTestId('input-org-limit-value').fill('75');
        await page.getByTestId('button-org-limit-save').click();

        await expect(page.getByTestId('org-limit-disabled')).toBeVisible();
        await expect(page.getByTestId('button-org-limit-save')).toBeDisabled();
      });

      test('should show an error when the limit cannot be loaded', async ({
        page,
      }) => {
        await mockOrgBuildLimitError(page, 500);
        await loadOrg(page);

        await expect(page.getByTestId('org-limit-error')).toBeVisible();
        await expect(page.getByTestId('alert')).toContainText('Error');
      });
    });

    test.describe('repository limit', () => {
      test('loading a repo should show its current limit', async ({ page }) => {
        await page.getByTestId('input-repo-limit-org').fill('github');
        await page.getByTestId('input-repo-limit-name').fill('octocat');
        await page.getByTestId('button-repo-limit-load').click();

        await expect(page.getByTestId('repo-limit-current')).toContainText(
          'github/octocat',
        );
        await expect(page.getByTestId('input-repo-limit-value')).toHaveValue(
          '10',
        );
      });

      test('repo org should be prefilled from the loaded org', async ({
        page,
      }) => {
        await loadOrg(page);

        await expect(page.getByTestId('input-repo-limit-org')).toHaveValue(
          'github',
        );
      });

      test('updating the limit should show a success alert', async ({
        page,
      }) => {
        await page.getByTestId('input-repo-limit-org').fill('github');
        await page.getByTestId('input-repo-limit-name').fill('octocat');
        await page.getByTestId('button-repo-limit-load').click();

        const repoUpdated = readTestData<{ build_limit: number }>(
          'repository_updated.json',
        );

        await expect(page.getByTestId('button-repo-limit-save')).toBeDisabled();
        await page
          .getByTestId('input-repo-limit-value')
          .fill(String(repoUpdated.build_limit));
        await page.getByTestId('button-repo-limit-save').click();

        await expect(page.getByTestId('alert')).toContainText(
          `maximum concurrent build limit set to '${repoUpdated.build_limit}'`,
        );
        await expect(page.getByTestId('button-repo-limit-save')).toBeDisabled();
      });
    });
  });

  test.describe('with org build limits disabled on the server', () => {
    test.beforeEach(async ({ page, app }) => {
      const settings = readTestData<Record<string, unknown>>('settings.json');
      await mockAdminSettings(page, {
        ...settings,
        enable_org_build_limit: false,
      });
      await mockRepoDetail(page, 'repository.json');
      await mockOrgBuildLimit(page, 'org_limit_default.json');
      await app.loginAdmin('/admin/build-limits');
    });

    test('should show the org section disabled with a note', async ({
      page,
    }) => {
      await expect(page.getByTestId('org-limit')).toBeVisible();
      await expect(page.getByTestId('org-limit-disabled')).toContainText(
        'Organization build limits are disabled by the deployment setting: VELA_ENABLE_ORG_BUILD_LIMIT',
      );
      await expect(page.getByTestId('input-org-limit-org')).toBeDisabled();
      await expect(page.getByTestId('button-org-limit-load')).toBeDisabled();
    });

    test('should keep the repo section enabled', async ({ page }) => {
      await expect(page.getByTestId('input-repo-limit-org')).toBeEnabled();
      await expect(page.getByTestId('input-repo-limit-name')).toBeEnabled();
    });
  });
});
