<!--
  Copyright (C) 2023 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <cv-text-input
              :label="$t('settings.domain')"
              v-model="domain"
              placeholder="fornitori.cliente.it"
              :disabled="loading.getConfiguration || loading.configureModule"
              :invalid-message="error.domain"
              ref="domain"
            ></cv-text-input>
            <cv-text-input
              :label="$t('settings.customer_name')"
              v-model="customerName"
              :placeholder="$t('settings.customer_name')"
              :disabled="loading.getConfiguration || loading.configureModule"
              :invalid-message="error.customerName"
              ref="customerName"
            ></cv-text-input>
            <cv-text-input
              :label="$t('settings.installation_id')"
              :helper-text="$t('settings.installation_id_helper')"
              v-model="installationId"
              placeholder="cliente-prod-01"
              :disabled="loading.getConfiguration || loading.configureModule"
              :invalid-message="error.installationId"
              ref="installationId"
            ></cv-text-input>
            <cv-text-input
              :label="$t('settings.admin_email')"
              v-model="adminEmail"
              placeholder="admin@cliente.it"
              :disabled="loading.getConfiguration || loading.configureModule"
              :invalid-message="error.adminEmail"
              ref="adminEmail"
            ></cv-text-input>
            <cv-text-input
              type="password"
              :label="$t('settings.admin_password')"
              :helper-text="$t('settings.admin_password_helper')"
              v-model="adminPassword"
              :disabled="loading.getConfiguration || loading.configureModule"
              :invalid-message="error.adminPassword"
              ref="adminPassword"
            ></cv-text-input>
            <cv-row v-if="error.configureModule">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.configure-module')"
                  :description="error.configureModule"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="loading.getConfiguration || loading.configureModule"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>
<script>
import to from "await-to-js";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";
export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      urlCheckInterval: null,
      domain: "",
      customerName: "",
      installationId: "",
      adminEmail: "",
      adminPassword: "",
      loading: {
        getConfiguration: false,
        configureModule: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        domain: "",
        customerName: "",
        installationId: "",
        adminEmail: "",
        adminPassword: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  created() {
    this.getConfiguration();
  },
  methods: {
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      this.loading.getConfiguration = false;
      const config = taskResult.output;
      this.domain = config.domain || "";
      this.customerName = config.customer_name || "";
      this.installationId = config.installation_id || "";
      this.adminEmail = config.admin_email || "";
      // la password non viene mai restituita da get-configuration (segreto)
      this.focusElement("domain");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      let isValidationOk = true;
      let focusAlreadySet = false;
      if (!this.domain || !/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(this.domain)) {
        this.error.domain = this.domain
          ? this.$t("settings.invalid_domain")
          : this.$t("common.required");
        if (!focusAlreadySet) {
          this.focusElement("domain");
          focusAlreadySet = true;
        }
        isValidationOk = false;
      }
      if (!this.customerName) {
        this.error.customerName = this.$t("common.required");
        if (!focusAlreadySet) {
          this.focusElement("customerName");
          focusAlreadySet = true;
        }
        isValidationOk = false;
      }
      if (!this.installationId || !/^[a-zA-Z0-9._-]+$/.test(this.installationId)) {
        this.error.installationId = this.installationId
          ? this.$t("settings.invalid_installation_id")
          : this.$t("common.required");
        if (!focusAlreadySet) {
          this.focusElement("installationId");
          focusAlreadySet = true;
        }
        isValidationOk = false;
      }
      if (!this.adminEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.adminEmail)) {
        this.error.adminEmail = this.adminEmail
          ? this.$t("settings.invalid_email")
          : this.$t("common.required");
        if (!focusAlreadySet) {
          this.focusElement("adminEmail");
          focusAlreadySet = true;
        }
        isValidationOk = false;
      }
      if (this.adminPassword && this.adminPassword.length < 12) {
        this.error.adminPassword = this.$t("settings.invalid_password_length");
        if (!focusAlreadySet) {
          this.focusElement("adminPassword");
          focusAlreadySet = true;
        }
        isValidationOk = false;
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;
      for (const validationError of validationErrors) {
        const field = validationError.field;
        if (field !== "(root)") {
          this.error[field] = this.$t("settings." + validationError.error);
          if (!focusAlreadySet) {
            this.focusElement(field);
            focusAlreadySet = true;
          }
        }
      }
    },
    async configureModule() {
      const isValidationOk = this.validateConfigureModule();
      if (!isValidationOk) {
        return;
      }
      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );
      const data = {
        domain: this.domain,
        customer_name: this.customerName,
        installation_id: this.installationId,
        admin_email: this.adminEmail,
      };
      if (this.adminPassword) {
        data.admin_password = this.adminPassword;
      }
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data,
          extra: {
            title: this.$t("settings.configure_instance", {
              instance: this.instanceName,
            }),
            description: this.$t("common.processing"),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;
      this.adminPassword = "";
      this.getConfiguration();
    },
  },
};
</script>
<style scoped lang="scss">
@import "../styles/carbon-utils";
</style>
