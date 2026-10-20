# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

This project adheres to Azure [API Versioning](https://docs.microsoft.com/en-us/azure/api-management/api-management-versions) with [Revisions](https://docs.microsoft.com/en-us/azure/api-management/api-management-revisions) enabled.

Each version and revision is followed by a date of change, specially for under development versions. Each entry provides the following information (when applicable):

- **Breaking Changes**: changes that may certainty affect consumers of the API or how it is expected to be used.
- **Major Changes**: big improvements in the code, like adding or enabling features, or bug fixes.
- **Minor Changes**: small changes that have little impact, like spell checks in an API's documentation, adding or removing comments, etc.
- **Technical Debt / TODOs**: known internal limitations, workarounds, or maintenance tasks pending resolution that should be addressed in future versions.

Also, any bug fix must start with the prefix "Bug fix:" followed by the description of the changes _per se_.

Previous classification is not required if changes are simple or all belong to the same category.

> The solution version is defined in the `VersionPrefix` property within the `Directory.Build.props` file. This version must be updated accordingly with this changelog.
