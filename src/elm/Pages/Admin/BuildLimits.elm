{--
SPDX-License-Identifier: Apache-2.0
--}


module Pages.Admin.BuildLimits exposing (Model, Msg, page)

import Auth
import Components.Form
import Components.Loading
import Effect exposing (Effect)
import Html exposing (Html, div, h2, i, p, section, span, strong, text)
import Html.Attributes exposing (class)
import Http
import Http.Detailed
import Layouts
import Page exposing (Page)
import RemoteData exposing (WebData)
import Route exposing (Route)
import Shared
import String
import Utils.Errors as Errors
import Utils.Helpers as Util
import Vela exposing (defaultRepoPayload)
import View exposing (View)


{-| page : shared model, route, and returns the page.
-}
page : Auth.User -> Shared.Model -> Route () -> Page Model Msg
page user shared route =
    Page.new
        { init = init shared
        , update = update shared
        , subscriptions = subscriptions
        , view = view shared
        }
        |> Page.withLayout (toLayout user)



-- LAYOUT


{-| toLayout : takes model and passes the page info to Layouts.
-}
toLayout : Auth.User -> Model -> Layouts.Layout Msg
toLayout user model =
    Layouts.Default_Admin
        { navButtons = []
        , utilButtons = []
        , helpCommands = []
        , crumbs =
            [ ( "Admin", Nothing )
            ]
        }



-- INIT


{-| Model : alias for model for the page.
-}
type alias Model =
    { settings : WebData Vela.PlatformSettings
    , orgIn : String
    , loadedOrg : String
    , orgLimit : WebData Vela.OrgBuildLimit
    , orgLimitIn : String
    , orgLimitForbidden : Bool
    , confirmingReset : Bool
    , repoOrgIn : String
    , repoNameIn : String
    , repo : WebData Vela.Repository
    , repoLimitIn : String
    }


{-| init : initializes page with no arguments.
-}
init : Shared.Model -> () -> ( Model, Effect Msg )
init shared () =
    ( { settings = RemoteData.Loading
      , orgIn = ""
      , loadedOrg = ""
      , orgLimit = RemoteData.NotAsked
      , orgLimitIn = ""
      , orgLimitForbidden = False
      , confirmingReset = False
      , repoOrgIn = ""
      , repoNameIn = ""
      , repo = RemoteData.NotAsked
      , repoLimitIn = ""
      }
    , Effect.getSettings
        { baseUrl = shared.velaAPIBaseURL
        , session = shared.session
        , onResponse = GetSettingsResponse
        }
    )



-- UPDATE


{-| Msg : custom type with possible messages.
-}
type Msg
    = GetSettingsResponse (Result (Http.Detailed.Error String) ( Http.Metadata, Vela.PlatformSettings ))
      -- ORG LIMIT
    | OrgOnInput String
    | OrgLoadOnClick
    | GetOrgLimitResponse String (Result (Http.Detailed.Error String) ( Http.Metadata, Vela.OrgBuildLimit ))
    | OrgLimitOnInput String
    | OrgLimitSaveOnClick
    | UpdateOrgLimitResponse (Result (Http.Detailed.Error String) ( Http.Metadata, Vela.OrgBuildLimit ))
    | OrgLimitResetOnClick
    | OrgLimitResetCancelOnClick
    | OrgLimitResetConfirmOnClick
    | DeleteOrgLimitResponse (Result (Http.Detailed.Error String) ( Http.Metadata, String ))
      -- REPO LIMIT
    | RepoOrgOnInput String
    | RepoNameOnInput String
    | RepoLoadOnClick
    | GetRepoResponse (Result (Http.Detailed.Error String) ( Http.Metadata, Vela.Repository ))
    | RepoLimitOnInput String
    | RepoLimitSaveOnClick
    | UpdateRepoResponse (Result (Http.Detailed.Error String) ( Http.Metadata, Vela.Repository ))


{-| update : takes current models, message, and returns an updated model and effect.
-}
update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GetSettingsResponse response ->
            case response of
                Ok ( _, settings ) ->
                    ( { model | settings = RemoteData.Success settings }
                    , Effect.none
                    )

                Err error ->
                    ( { model | settings = Errors.toFailure error }
                    , Effect.handleHttpError
                        { error = error
                        , shouldShowAlertFn = Errors.showAlertAlways
                        }
                    )

        -- ORG LIMIT
        OrgOnInput val ->
            ( { model | orgIn = val }
            , Effect.none
            )

        OrgLoadOnClick ->
            let
                org =
                    String.trim model.orgIn
            in
            if String.isEmpty org then
                ( model, Effect.none )

            else
                ( { model
                    | loadedOrg = org
                    , orgLimit = RemoteData.Loading
                    , confirmingReset = False
                    , repoOrgIn =
                        if String.isEmpty model.repoOrgIn then
                            org

                        else
                            model.repoOrgIn
                  }
                , Effect.getOrgBuildLimit
                    { baseUrl = shared.velaAPIBaseURL
                    , session = shared.session
                    , onResponse = GetOrgLimitResponse org
                    , org = org
                    }
                )

        GetOrgLimitResponse requestedOrg response ->
            -- ignore responses for an org that is no longer the loaded org
            if String.toLower requestedOrg /= String.toLower model.loadedOrg then
                ( model, Effect.none )

            else
                case response of
                    Ok ( _, orgLimit ) ->
                        ( { model
                            | orgLimit = RemoteData.Success orgLimit
                            , orgLimitIn = String.fromInt orgLimit.buildLimit
                            , confirmingReset = False
                          }
                        , Effect.none
                        )

                    Err error ->
                        ( { model | orgLimit = Errors.toFailure error }
                        , Effect.handleHttpError
                            { error = error
                            , shouldShowAlertFn = Errors.showAlertAlways
                            }
                        )

        OrgLimitOnInput val ->
            ( { model | orgLimitIn = Components.Form.handleNumberInputString model.orgLimitIn val }
            , Effect.none
            )

        OrgLimitSaveOnClick ->
            case String.toInt model.orgLimitIn of
                Just limit ->
                    if orgLimitDisabled model then
                        ( model, Effect.none )

                    else
                        ( model
                        , Effect.updateOrgBuildLimit
                            { baseUrl = shared.velaAPIBaseURL
                            , session = shared.session
                            , onResponse = UpdateOrgLimitResponse
                            , org = model.loadedOrg
                            , body = Http.jsonBody <| Vela.encodeOrgBuildLimitPayload limit
                            }
                        )

                Nothing ->
                    ( model, Effect.none )

        UpdateOrgLimitResponse response ->
            case response of
                Ok ( _, orgLimit ) ->
                    ( { model
                        | orgLimit = RemoteData.Success orgLimit
                        , orgLimitIn = String.fromInt orgLimit.buildLimit
                        , orgLimitForbidden = False
                      }
                    , Effect.addAlertSuccess
                        { content =
                            "Build limit for org '"
                                ++ model.loadedOrg
                                ++ "' set to '"
                                ++ String.fromInt orgLimit.buildLimit
                                ++ "'."
                        , addToastIfUnique = False
                        , link = Nothing
                        }
                    )

                Err error ->
                    case error of
                        Http.Detailed.BadStatus meta _ ->
                            if meta.statusCode == 403 then
                                ( { model | orgLimitForbidden = True }
                                , Effect.none
                                )

                            else
                                ( model
                                , Effect.handleHttpError
                                    { error = error
                                    , shouldShowAlertFn = Errors.showAlertAlways
                                    }
                                )

                        _ ->
                            ( model
                            , Effect.handleHttpError
                                { error = error
                                , shouldShowAlertFn = Errors.showAlertAlways
                                }
                            )

        OrgLimitResetOnClick ->
            ( { model | confirmingReset = True }
            , Effect.none
            )

        OrgLimitResetCancelOnClick ->
            ( { model | confirmingReset = False }
            , Effect.none
            )

        OrgLimitResetConfirmOnClick ->
            if orgLimitDisabled model then
                ( { model | confirmingReset = False }, Effect.none )

            else
                ( { model | confirmingReset = False }
                , Effect.deleteOrgBuildLimit
                    { baseUrl = shared.velaAPIBaseURL
                    , session = shared.session
                    , onResponse = DeleteOrgLimitResponse
                    , org = model.loadedOrg
                    }
                )

        DeleteOrgLimitResponse response ->
            case response of
                Ok _ ->
                    ( { model | orgLimit = RemoteData.Loading }
                    , Effect.batch
                        [ Effect.addAlertSuccess
                            { content = "Build limit override for org '" ++ model.loadedOrg ++ "' removed. The server default now applies."
                            , addToastIfUnique = False
                            , link = Nothing
                            }
                        , Effect.getOrgBuildLimit
                            { baseUrl = shared.velaAPIBaseURL
                            , session = shared.session
                            , onResponse = GetOrgLimitResponse model.loadedOrg
                            , org = model.loadedOrg
                            }
                        ]
                    )

                Err error ->
                    ( model
                    , Effect.handleHttpError
                        { error = error
                        , shouldShowAlertFn = Errors.showAlertAlways
                        }
                    )

        -- REPO LIMIT
        RepoOrgOnInput val ->
            ( { model | repoOrgIn = val }
            , Effect.none
            )

        RepoNameOnInput val ->
            ( { model | repoNameIn = val }
            , Effect.none
            )

        RepoLoadOnClick ->
            let
                org =
                    String.trim model.repoOrgIn

                repo =
                    String.trim model.repoNameIn
            in
            if String.isEmpty org || String.isEmpty repo then
                ( model, Effect.none )

            else
                ( { model | repo = RemoteData.Loading }
                , Effect.getRepo
                    { baseUrl = shared.velaAPIBaseURL
                    , session = shared.session
                    , onResponse = GetRepoResponse
                    , org = org
                    , repo = repo
                    }
                )

        GetRepoResponse response ->
            case response of
                Ok ( _, repo ) ->
                    ( { model
                        | repo = RemoteData.Success repo
                        , repoLimitIn = String.fromInt repo.limit
                      }
                    , Effect.none
                    )

                Err error ->
                    ( { model | repo = Errors.toFailure error }
                    , Effect.handleHttpError
                        { error = error
                        , shouldShowAlertFn = Errors.showAlertAlways
                        }
                    )

        RepoLimitOnInput val ->
            ( { model | repoLimitIn = Components.Form.handleNumberInputString model.repoLimitIn val }
            , Effect.none
            )

        RepoLimitSaveOnClick ->
            case ( model.repo, String.toInt model.repoLimitIn ) of
                ( RemoteData.Success repo, Just limit ) ->
                    let
                        payload =
                            { defaultRepoPayload
                                | limit = Just limit
                            }
                    in
                    ( model
                    , Effect.updateRepo
                        { baseUrl = shared.velaAPIBaseURL
                        , session = shared.session
                        , onResponse = UpdateRepoResponse
                        , org = repo.org
                        , repo = repo.name
                        , body = Http.jsonBody <| Vela.encodeRepoPayload payload
                        }
                    )

                _ ->
                    ( model, Effect.none )

        UpdateRepoResponse response ->
            case response of
                Ok ( _, repo ) ->
                    ( { model
                        | repo = RemoteData.Success repo
                        , repoLimitIn = String.fromInt repo.limit
                      }
                    , Effect.addAlertSuccess
                        { content = "Repo '" ++ repo.full_name ++ "' maximum concurrent build limit set to '" ++ String.fromInt repo.limit ++ "'."
                        , addToastIfUnique = False
                        , link = Nothing
                        }
                    )

                Err error ->
                    ( model
                    , Effect.handleHttpError
                        { error = error
                        , shouldShowAlertFn = Errors.showAlertAlways
                        }
                    )



-- SUBSCRIPTIONS


{-| subscriptions : takes model and returns that there are no subscriptions.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


{-| view : takes models and creates the html for the page.
-}
view : Shared.Model -> Model -> View Msg
view shared model =
    { title = ""
    , body =
        [ div [ class "admin-settings" ]
            [ viewOrgSection shared model
            , viewRepoSection shared model
            ]
        ]
    }


{-| orgLimitDisabled : returns true unless the platform settings report organization build limits as enabled.
-}
orgLimitDisabled : Model -> Bool
orgLimitDisabled model =
    model.orgLimitForbidden
        || RemoteData.unwrap True (not << .enableOrgBuildLimit) model.settings


{-| viewOrgSection : renders the section for viewing and changing an organization build limit.
-}
viewOrgSection : Shared.Model -> Model -> Html Msg
viewOrgSection shared model =
    section [ class "settings", Util.testAttribute "org-limit" ]
        [ viewHeader "Organization Limit"
        , viewDescription "Concurrent builds (pending or running) across all repositories in an organization. New builds are rejected once the organization reaches its limit."
        , if orgLimitDisabled model then
            p [ class "notice", Util.testAttribute "org-limit-disabled" ]
                [ text "Organization build limits are disabled by the deployment setting: VELA_ENABLE_ORG_BUILD_LIMIT" ]

          else
            text ""
        , div [ class "form-controls" ]
            [ Components.Form.viewInput
                { title = Nothing
                , subtitle = Nothing
                , id_ = "org-limit-org"
                , val = model.orgIn
                , placeholder_ = "org"
                , classList_ = []
                , wrapperClassList = [ ( "-wide", True ) ]
                , rows_ = Nothing
                , wrap_ = Nothing
                , msg = OrgOnInput
                , disabled_ = orgLimitDisabled model
                , min = Nothing
                , max = Nothing
                , required = False
                }
            , Components.Form.viewButton
                { id_ = "org-limit-load"
                , msg = OrgLoadOnClick
                , text_ = "load"
                , classList_ = [ ( "-outline", True ) ]
                , disabled_ = orgLimitDisabled model || (String.isEmpty <| String.trim model.orgIn)
                }
            ]
        , case model.orgLimit of
            RemoteData.NotAsked ->
                text ""

            RemoteData.Loading ->
                Components.Loading.viewSmallLoader

            RemoteData.Failure _ ->
                p [ Util.testAttribute "org-limit-error" ]
                    [ text <| "Unable to load the build limit for org '" ++ model.loadedOrg ++ "'." ]

            RemoteData.Success orgLimit ->
                viewOrgLimit shared model orgLimit
        ]


{-| viewOrgLimit : renders the loaded organization build limit with its edit controls.
-}
viewOrgLimit : Shared.Model -> Model -> Vela.OrgBuildLimit -> Html Msg
viewOrgLimit shared model orgLimit =
    let
        hasOverride =
            orgLimit.id /= Nothing

        saveDisabled =
            case String.toInt model.orgLimitIn of
                Just limit ->
                    orgLimitDisabled model
                        || (limit < 1)
                        || (hasOverride && limit == orgLimit.buildLimit)

                Nothing ->
                    True
    in
    div [ Util.testAttribute "org-limit-details" ]
        [ p [ class "settings-info", Util.testAttribute "org-limit-status" ]
            [ strong [] [ text <| "Org '" ++ model.loadedOrg ++ "': " ]
            , span []
                [ text <|
                    if hasOverride then
                        "custom override"

                    else
                        "server default"
                ]
            ]
        , if hasOverride && not (String.isEmpty orgLimit.updatedBy) then
            p [ class "settings-info", Util.testAttribute "org-limit-updated" ]
                [ text "Last updated on "
                , i [] [ text <| Util.humanReadableDateTimeWithDefault shared.zone orgLimit.updatedAt ]
                , text " by "
                , i [] [ text orgLimit.updatedBy ]
                , text "."
                ]

          else
            text ""
        , div [ class "form-controls" ]
            [ Components.Form.viewNumberInput
                { title = Nothing
                , subtitle = Nothing
                , id_ = "org-limit-value"
                , val = model.orgLimitIn
                , placeholder_ = ""
                , wrapperClassList = [ ( "-wide", True ) ]
                , classList_ = []
                , rows_ = Nothing
                , wrap_ = Nothing
                , msg = OrgLimitOnInput
                , disabled_ = orgLimitDisabled model
                , min = Just 1
                , max = Nothing
                , required = False
                }
            , Components.Form.viewButton
                { id_ = "org-limit-save"
                , msg = OrgLimitSaveOnClick
                , text_ = "update"
                , classList_ = [ ( "-outline", True ) ]
                , disabled_ = saveDisabled
                }
            ]
        , if hasOverride then
            div [ class "form-controls" ] <|
                if model.confirmingReset then
                    [ Components.Form.viewButton
                        { id_ = "org-limit-reset-cancel"
                        , msg = OrgLimitResetCancelOnClick
                        , text_ = "Cancel"
                        , classList_ = [ ( "-outline", True ) ]
                        , disabled_ = orgLimitDisabled model
                        }
                    , Components.Form.viewButton
                        { id_ = "org-limit-reset-confirm"
                        , msg = OrgLimitResetConfirmOnClick
                        , text_ = "Confirm Reset"
                        , classList_ = [ ( "-secret-delete-confirm", True ) ]
                        , disabled_ = orgLimitDisabled model
                        }
                    ]

                else
                    [ Components.Form.viewButton
                        { id_ = "org-limit-reset"
                        , msg = OrgLimitResetOnClick
                        , text_ = "Reset to default"
                        , classList_ = [ ( "-outline", True ) ]
                        , disabled_ = orgLimitDisabled model
                        }
                    ]

          else
            text ""
        , p [ class "settings-info" ]
            [ text "Limits must be at least 1." ]
        ]


{-| viewRepoSection : renders the section for viewing and changing a repository build limit.
-}
viewRepoSection : Shared.Model -> Model -> Html Msg
viewRepoSection shared model =
    section [ class "settings", Util.testAttribute "repo-limit" ]
        [ viewHeader "Repository Limit"
        , viewDescription "Concurrent builds (pending or running) that exceed this limit will be stopped."
        , div [ class "form-controls" ]
            [ Components.Form.viewInput
                { title = Nothing
                , subtitle = Nothing
                , id_ = "repo-limit-org"
                , val = model.repoOrgIn
                , placeholder_ = "org"
                , classList_ = []
                , wrapperClassList = [ ( "-wide", True ) ]
                , rows_ = Nothing
                , wrap_ = Nothing
                , msg = RepoOrgOnInput
                , disabled_ = False
                , min = Nothing
                , max = Nothing
                , required = False
                }
            , Components.Form.viewInput
                { title = Nothing
                , subtitle = Nothing
                , id_ = "repo-limit-name"
                , val = model.repoNameIn
                , placeholder_ = "repo"
                , classList_ = []
                , wrapperClassList = [ ( "-wide", True ) ]
                , rows_ = Nothing
                , wrap_ = Nothing
                , msg = RepoNameOnInput
                , disabled_ = False
                , min = Nothing
                , max = Nothing
                , required = False
                }
            , Components.Form.viewButton
                { id_ = "repo-limit-load"
                , msg = RepoLoadOnClick
                , text_ = "load"
                , classList_ = [ ( "-outline", True ) ]
                , disabled_ = String.isEmpty (String.trim model.repoOrgIn) || String.isEmpty (String.trim model.repoNameIn)
                }
            ]
        , case model.repo of
            RemoteData.NotAsked ->
                text ""

            RemoteData.Loading ->
                Components.Loading.viewSmallLoader

            RemoteData.Failure _ ->
                p [ Util.testAttribute "repo-limit-error" ]
                    [ text "Unable to load the repo." ]

            RemoteData.Success repo ->
                viewRepoLimit shared model repo
        ]


{-| viewRepoLimit : renders the loaded repository build limit with its edit controls.
-}
viewRepoLimit : Shared.Model -> Model -> Vela.Repository -> Html Msg
viewRepoLimit shared model repo =
    div [ Util.testAttribute "repo-limit-details" ]
        [ p [ class "settings-info", Util.testAttribute "repo-limit-current" ]
            [ strong [] [ text <| "Repo '" ++ repo.full_name ++ "': " ]
            , span [] [ text <| String.fromInt repo.limit ]
            ]
        , div [ class "form-controls" ]
            [ Components.Form.viewNumberInput
                { title = Nothing
                , subtitle = Nothing
                , id_ = "repo-limit-value"
                , val = model.repoLimitIn
                , placeholder_ = ""
                , wrapperClassList = [ ( "-wide", True ) ]
                , classList_ = []
                , rows_ = Nothing
                , wrap_ = Nothing
                , msg = RepoLimitOnInput
                , disabled_ = False
                , min = Just 1
                , max = Just shared.velaMaxBuildLimit
                , required = False
                }
            , Components.Form.viewButton
                { id_ = "repo-limit-save"
                , msg = RepoLimitSaveOnClick
                , text_ = "update"
                , classList_ = [ ( "-outline", True ) ]
                , disabled_ = not <| validRepoLimit shared.velaMaxBuildLimit repo model.repoLimitIn
                }
            ]
        , p [ class "settings-info" ]
            [ text <| "Limits must lie between 1 and " ++ String.fromInt shared.velaMaxBuildLimit ++ "." ]
        ]


{-| validRepoLimit : takes the max limit, repo, and user entered limit and returns whether it is a valid update.
-}
validRepoLimit : Int -> Vela.Repository -> String -> Bool
validRepoLimit maxLimit repo val =
    case String.toInt val of
        Just limit ->
            limit >= 1 && limit <= maxLimit && limit /= repo.limit

        Nothing ->
            False


{-| viewHeader : renders header view for a settings section.
-}
viewHeader : String -> Html Msg
viewHeader title =
    h2 [ class "settings-title" ]
        [ text title ]


{-| viewDescription : renders description view for a settings section.
-}
viewDescription : String -> Html Msg
viewDescription description =
    p [ class "settings-description" ]
        [ text description ]
